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

struct Account: Codable, Identifiable {
    let id: String
    let type: String
    let subtype: String
    let name: String
    let number: String
    let balance: String
    let currencyCode: String
    let creditData: CreditData?

    struct CreditData: Codable {
        let balanceDueDate: String?
        let availableCreditLimit: String?
    }

    var title: String { name.trimmingCharacters(in: .whitespaces) }
    var value: Decimal { Decimal(string: balance) ?? 0 }
}

struct Transaction: Codable, Identifiable {
    let id: String
    let date: Date
    let description: String
    let amount: String
    let currencyCode: String
    let category: String?
    var account: String?   // filled in after decoding; optional so a missing key does not fail the decode

    var value: Decimal { Decimal(string: amount) ?? 0 }
}

struct StripeSummary: Codable {
    let currency: String
    let available: Decimal
    let monthRevenue: Decimal
}

struct CategorySpend: Identifiable {
    let name: String
    let thisMonth: Decimal
    let lastMonth: Decimal
    var id: String { name }
}

struct FinanceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Read-only mirror of Banco MCP (Open Finance Brasil). Last fetch is cached as JSON so the view opens offline.
@Observable final class Finance {
    var accounts: [Account] = []
    var transactions: [Transaction] = []
    var fetched: Date?
    var error: String?
    var loading = false
    var stripe: StripeSummary?

    static let keyAccount = "bancomcp"
    static let stripeAccount = "stripe"
    static let cacheURL = URL.applicationSupportDirectory.appending(path: "Wave/finance.json")

    private struct Snapshot: Codable {
        var accounts: [Account]
        var transactions: [Transaction]
        var fetched: Date
        var stripe: StripeSummary?
    }

    private struct Envelope<T: Decodable>: Decodable {
        let ok: Bool
        let error: String?
        let result: Inner?
        struct Inner: Decodable { let results: [T] }
    }

    var hasKey: Bool { Keychain.get(Self.keyAccount) != nil }

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.cacheURL), let s = try? decoder.decode(Snapshot.self, from: data) else { return }
        accounts = s.accounts
        transactions = s.transactions
        fetched = s.fetched
        stripe = s.stripe
    }

    /// Spend per category, this calendar month against the previous one. Credits are left out.
    var categories: [CategorySpend] {
        let cal = Calendar.current
        let thisStart = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        let lastStart = cal.date(byAdding: .month, value: -1, to: thisStart)!
        var totals: [String: (Decimal, Decimal)] = [:]
        for t in transactions where t.value < 0 {
            let name = t.category ?? "Uncategorized"
            var row = totals[name] ?? (0, 0)
            if t.date >= thisStart { row.0 -= t.value } else if t.date >= lastStart { row.1 -= t.value }
            totals[name] = row
        }
        return totals.map { CategorySpend(name: $0.key, thisMonth: $0.value.0, lastMonth: $0.value.1) }
            .filter { $0.thisMonth > 0 || $0.lastMonth > 0 }
            .sorted { $0.thisMonth > $1.thisMonth }
    }

    func monthTotals() -> (spent: Decimal, income: Decimal) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        let month = transactions.filter { $0.date >= start }
        return (-month.filter { $0.value < 0 }.reduce(0) { $0 + $1.value }, month.filter { $0.value > 0 }.reduce(0) { $0 + $1.value })
    }

    func refresh() async {
        guard let key = Keychain.get(Self.keyAccount) else { error = "No API key yet."; return }
        loading = true
        defer { loading = false }
        do {
            let accounts: [Account] = try await post("accounts/list", [:], key: key)
            let from = Calendar.current.date(byAdding: .day, value: -62, to: .now)!.formatted(.iso8601.year().month().day())
            let to = Date.now.formatted(.iso8601.year().month().day())
            var all: [Transaction] = []
            for account in accounts {
                var page: [Transaction] = try await post("transactions/list",
                    ["account_id": account.id, "from": from, "to": to, "page": 1, "page_size": 500], key: key)
                for i in page.indices { page[i].account = account.title }
                all += page
            }
            self.accounts = accounts
            transactions = all.sorted { $0.date > $1.date }
            if let stripeKey = Keychain.get(Self.stripeAccount) { stripe = try? await stripeSummary(key: stripeKey) } else { stripe = nil }
            fetched = .now
            error = nil
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? encoder.encode(Snapshot(accounts: accounts, transactions: transactions, fetched: .now, stripe: stripe)).write(to: Self.cacheURL)
        } catch {
            self.error = error.localizedDescription
        }
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

    private func post<T: Decodable>(_ endpoint: String, _ body: [String: Any], key: String) async throws -> [T] {
        var request = URLRequest(url: URL(string: "https://api.mcp.ai/api/openfinance/" + endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw FinanceError(message: "HTTP \(status): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? .distantPast
        }
        let envelope = try decoder.decode(Envelope<T>.self, from: data)
        guard envelope.ok, let result = envelope.result else { throw FinanceError(message: envelope.error ?? "Banco MCP returned ok=false") }
        return result.results
    }
}
