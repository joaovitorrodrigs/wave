import Foundation
import Observation
import Security

enum Keychain {
    static let service = "pro.wavestudio.wave"

    static func get(_ account: String) -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        SecItemAdd(query.merging([kSecValueData as String: Data(value.utf8)]) { $1 } as CFDictionary, nil)
    }
}

/// Read-only mirror of Banco MCP plus Stripe: twelve months of transactions kept on disk and topped up on
/// every refresh, accounts, card bills, investments, categories, and a daily net-worth point.
@Observable final class Finance {
    var snapshot = FinanceSnapshot.load()
    var error: String?
    var loading = false

    static let keyAccount = "bancomcp"
    static let stripeAccount = "stripe"

    var accounts: [Account] { snapshot.accounts }
    var transactions: [Transaction] { snapshot.transactions }
    var stripe: StripeSummary? { snapshot.stripe }
    var fetched: Date? { snapshot.fetched }
    var hasKey: Bool { Keychain.get(Self.keyAccount) != nil }

    func load() { snapshot = FinanceSnapshot.load() }

    func refresh() async {
        guard let key = Keychain.get(Self.keyAccount) else { error = "No API key yet."; return }
        loading = true
        defer { loading = false }
        do {
            var s = snapshot
            let cal = Calendar.current
            let day = Date.ISO8601FormatStyle().year().month().day()
            s.accounts = try await post("accounts/list", [:], key: key)

            // Transactions: everything since the last fetch (with a week of overlap), or a year on the first run.
            let yearAgo = cal.date(byAdding: .month, value: -12, to: .now)!
            let from = s.fetched.map { max(cal.date(byAdding: .day, value: -7, to: $0)!, yearAgo) } ?? yearAgo
            var fresh: [Transaction] = []
            for account in s.accounts {
                var page = 1
                while true {
                    let (rows, pages): ([Transaction], Int) = try await postPaged("transactions/list",
                        ["account_id": account.id, "from": from.formatted(day), "to": Date.now.formatted(day), "page": page, "page_size": 500], key: key)
                    fresh += rows.map { var t = $0; t.account = account.title; t.accountId = account.id; return t }
                    if page >= pages { break }
                    page += 1
                    try await Task.sleep(for: .milliseconds(600))
                }
            }
            var byId = Dictionary(uniqueKeysWithValues: s.transactions.map { ($0.id, $0) })
            for t in fresh { byId[t.id] = t }
            s.transactions = byId.values.filter { $0.date >= yearAgo }.sorted { $0.date > $1.date }

            s.investments = (try? await post("investments/list", [:], key: key) as [Investment]) ?? s.investments
            var bills: [CardBill] = []
            for account in s.accounts where account.type == "CREDIT" {
                let rows: [CardBill] = (try? await post("credit-card-bills/list", ["account_id": account.id, "page": 1, "page_size": 6], key: key)) ?? []
                bills += rows.map { var b = $0; b.accountId = account.id; return b }
            }
            if !bills.isEmpty { s.bills = bills.sorted { $0.dueDate > $1.dueDate } }
            if s.categories.isEmpty || (s.categoriesFetched.map { Date.now.timeIntervalSince($0) > 7 * 86400 } ?? true) {
                if let cats: [CategoryInfo] = try? await post("categories/list", [:], key: key) { s.categories = cats; s.categoriesFetched = .now }
            }
            if let stripeKey = Keychain.get(Self.stripeAccount) { s.stripe = try? await stripeSummary(key: stripeKey) } else { s.stripe = nil }

            // One net-worth point per day.
            let today = cal.startOfDay(for: .now)
            let point = WorthPoint(date: today,
                                   accounts: s.accounts.filter { $0.type == "BANK" }.reduce(0) { $0 + $1.value },
                                   investments: s.investments.reduce(0) { $0 + $1.net },
                                   cardDebt: s.accounts.filter { $0.type == "CREDIT" }.reduce(0) { $0 + $1.value })
            s.worth.removeAll { cal.isDate($0.date, inSameDayAs: today) }
            s.worth.append(point)
            s.worth.sort { $0.date < $1.date }
            s.fetched = .now
            s.save()
            snapshot = s
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Derived numbers

    func month(_ offset: Int = 0) -> DateInterval {
        let cal = Calendar.current
        let start = cal.date(byAdding: .month, value: offset, to: cal.date(from: cal.dateComponents([.year, .month], from: .now))!)!
        return DateInterval(start: start, end: cal.date(byAdding: .month, value: 1, to: start)!)
    }

    func totals(_ rows: [Shown], in interval: DateInterval) -> (income: Decimal, spent: Decimal) {
        let inRange = rows.filter { !$0.ignored && interval.contains($0.date) }
        return (inRange.filter { $0.value > 0 }.reduce(0) { $0 + $1.value }, -inRange.filter { $0.value < 0 }.reduce(0) { $0 + $1.value })
    }

    func byCategory(_ rows: [Shown], in interval: DateInterval) -> [(name: String, amount: Decimal)] {
        var totals: [String: Decimal] = [:]
        for r in rows where !r.ignored && r.value < 0 && interval.contains(r.date) { totals[r.category, default: 0] -= r.value }
        return totals.map { ($0.key, $0.value) }.sorted { $0.amount > $1.amount }
    }

    /// Last twelve months, oldest first: (label, income, spent).
    func trend(_ rows: [Shown]) -> [(label: String, income: Decimal, spent: Decimal)] {
        (0..<12).reversed().map { offset in
            let m = month(-offset)
            let t = totals(rows, in: m)
            return (m.start.formatted(.dateTime.month(.abbreviated)), t.income, t.spent)
        }
    }

    // MARK: HTTP

    private func post<T: Decodable>(_ endpoint: String, _ body: [String: Any], key: String) async throws -> [T] {
        try await postPaged(endpoint, body, key: key).0
    }

    private struct Envelope<T: Decodable>: Decodable {
        let ok: Bool
        let error: String?
        let result: Inner?
        struct Inner: Decodable { let results: [T]; let totalPages: Int? }
    }

    private func postPaged<T: Decodable>(_ endpoint: String, _ body: [String: Any], key: String) async throws -> ([T], Int) {
        var request = URLRequest(url: URL(string: "https://api.mcp.ai/api/openfinance/" + endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FinanceError(message: "HTTP \(status): \(String(decoding: data.prefix(200), as: UTF8.self))") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? .distantPast
        }
        let envelope = try decoder.decode(Envelope<T>.self, from: data)
        guard envelope.ok, let result = envelope.result else { throw FinanceError(message: envelope.error ?? "Banco MCP returned ok=false") }
        return (result.results, result.totalPages ?? 1)
    }

    /// Stripe, read-only: available balance and this month's paid charges net of refunds.
    private func stripeSummary(key: String) async throws -> StripeSummary {
        func get(_ path: String) async throws -> [String: Any] {
            var request = URLRequest(url: URL(string: "https://api.stripe.com/v1/" + path)!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FinanceError(message: "Stripe: \(String(decoding: data.prefix(160), as: UTF8.self))")
            }
            return json
        }
        let balance = try await get("balance")
        let available = (balance["available"] as? [[String: Any]])?.first
        let currency = (available?["currency"] as? String ?? "brl").uppercased()
        let availableAmount = Decimal(available?["amount"] as? Int ?? 0) / 100
        let monthStart = Int(Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now))!.timeIntervalSince1970)
        let charges = try await get("charges?limit=100&created[gte]=\(monthStart)")
        let revenue = ((charges["data"] as? [[String: Any]]) ?? [])
            .filter { ($0["paid"] as? Bool) == true }
            .reduce(Decimal(0)) { $0 + Decimal(($1["amount"] as? Int ?? 0) - ($1["amount_refunded"] as? Int ?? 0)) / 100 }
        return StripeSummary(currency: currency, available: availableAmount, monthRevenue: revenue)
    }
}
