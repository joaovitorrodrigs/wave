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
    var account = ""

    var value: Decimal { Decimal(string: amount) ?? 0 }
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

    static let keyAccount = "bancomcp"
    static let cacheURL = URL.applicationSupportDirectory.appending(path: "Wave/finance.json")

    private struct Snapshot: Codable {
        var accounts: [Account]
        var transactions: [Transaction]
        var fetched: Date
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
    }

    func refresh() async {
        guard let key = Keychain.get(Self.keyAccount) else { error = "No API key yet."; return }
        loading = true
        defer { loading = false }
        do {
            let accounts: [Account] = try await post("accounts/list", [:], key: key)
            let from = Calendar.current.date(byAdding: .day, value: -30, to: .now)!.formatted(.iso8601.year().month().day())
            let to = Date.now.formatted(.iso8601.year().month().day())
            var all: [Transaction] = []
            for account in accounts {
                var page: [Transaction] = try await post("transactions/list",
                    ["account_id": account.id, "from": from, "to": to, "page": 1, "page_size": 200], key: key)
                for i in page.indices { page[i].account = account.title }
                all += page
            }
            self.accounts = accounts
            transactions = all.sorted { $0.date > $1.date }
            fetched = .now
            error = nil
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? encoder.encode(Snapshot(accounts: accounts, transactions: transactions, fetched: .now)).write(to: Self.cacheURL)
        } catch {
            self.error = error.localizedDescription
        }
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
