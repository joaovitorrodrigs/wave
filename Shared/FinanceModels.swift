import Foundation
import SwiftData

// MARK: - What Banco MCP and Stripe give us, as cached on disk

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
        let creditLimit: String?
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
    let categoryId: String?
    var account: String?
    var accountId: String?

    var value: Decimal { Decimal(string: amount) ?? 0 }
}

struct Investment: Codable, Identifiable {
    let id: String
    let name: String
    let type: String
    let subtype: String?
    let balance: String          // current, net of taxes if withdrawn now
    let amount: String?          // gross current
    let amountOriginal: String?  // what went in
    let taxes: String?
    let rate: Double?
    let rateType: String?
    let currencyCode: String

    var current: Decimal { Decimal(string: amount ?? balance) ?? 0 }
    var net: Decimal { Decimal(string: balance) ?? 0 }
    var invested: Decimal { Decimal(string: amountOriginal ?? "") ?? net }
    var grossYield: Decimal { current - invested }
    var netYield: Decimal { net - invested }
    var yieldPercent: Double { invested == 0 ? 0 : Double(truncating: (netYield / invested) as NSNumber) * 100 }
}

struct CardBill: Codable, Identifiable {
    let id: String
    let dueDate: Date
    let totalAmount: String
    let minimumPaymentAmount: String?
    let billClosingDate: Date?
    var accountId: String?
    var total: Decimal { Decimal(string: totalAmount) ?? 0 }
    var minimum: Decimal { Decimal(string: minimumPaymentAmount ?? "") ?? 0 }
}

struct CategoryInfo: Codable, Identifiable {
    let id: String
    let description: String
    let descriptionTranslated: String?
    let parentId: String?
    let parentDescription: String?
    var name: String { descriptionTranslated ?? description }
}

struct StripeSummary: Codable {
    let currency: String
    let available: Decimal
    let monthRevenue: Decimal
}

struct WorthPoint: Codable {
    let date: Date
    let accounts: Decimal
    let investments: Decimal
    let cardDebt: Decimal
    var total: Decimal { accounts + investments - cardDebt }
}

struct FinanceSnapshot: Codable {
    var accounts: [Account] = []
    var transactions: [Transaction] = []
    var investments: [Investment] = []
    var bills: [CardBill] = []
    var categories: [CategoryInfo] = []
    var worth: [WorthPoint] = []
    var stripe: StripeSummary?
    var fetched: Date?
    var categoriesFetched: Date?

    static let url = URL.applicationSupportDirectory.appending(path: "Wave/finance-v2.json")

    static func load() -> FinanceSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let s = try? decoder.decode(FinanceSnapshot.self, from: data) else { return FinanceSnapshot() }
        return s
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(self).write(to: Self.url, options: .atomic)
    }

    /// Parent category name for a transaction, so 130 categories read as a dozen groups.
    func group(for t: Transaction) -> String {
        guard let id = t.categoryId, let info = categories.first(where: { $0.id == id }) else { return t.category ?? "Uncategorized" }
        if let parent = info.parentId, let p = categories.first(where: { $0.id == parent }) { return p.name }
        return info.name
    }
}

struct FinanceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Rules and budgets, the user's layer on top

/// "If the description contains X": show it as Y, file it under a category, or leave it out of the totals.
@Model final class FinanceRule {
    var match: String
    var rename: String
    var category: String
    var ignore: Bool
    var created = Date.now

    init(match: String, rename: String = "", category: String = "", ignore: Bool = false) {
        self.match = match
        self.rename = rename
        self.category = category
        self.ignore = ignore
    }

    static func all(_ context: ModelContext) -> [FinanceRule] {
        (try? context.fetch(FetchDescriptor<FinanceRule>(sortBy: [SortDescriptor(\.created)]))) ?? []
    }
}

@Model final class Budget {
    var category: String
    var limit: Double
    init(category: String, limit: Double) { self.category = category; self.limit = limit }

    static func all(_ context: ModelContext) -> [Budget] {
        (try? context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.category)]))) ?? []
    }
}

/// A transaction after the rules: what to show, where to file it, whether it counts.
struct Shown: Identifiable {
    let raw: Transaction
    let title: String
    let category: String
    let ignored: Bool
    var id: String { raw.id }
    var value: Decimal { raw.value }
    var date: Date { raw.date }
}

extension FinanceSnapshot {
    func shown(_ rules: [FinanceRule]) -> [Shown] {
        transactions.map { t in
            var title = t.description, category = group(for: t), ignored = false
            for r in rules where !r.match.isEmpty && t.description.localizedCaseInsensitiveContains(r.match) {
                if !r.rename.isEmpty { title = r.rename }
                if !r.category.isEmpty { category = r.category }
                if r.ignore { ignored = true }
            }
            return Shown(raw: t, title: title, category: category, ignored: ignored)
        }
    }
}

/// A Phosphor icon for each of the bank's parent categories (Portuguese names), with a tag as the fallback.
enum CategoryIcon {
    static let map: [String: String] = [
        "Alimentos e bebidas": "fork-knife", "Apostas": "coins", "Compras": "shopping-bag", "Doações": "hand-heart",
        "Empréstimos e financiamento": "bank", "Impostos": "receipt", "Investimentos": "trend-up", "Lazer": "confetti",
        "Moradia": "house", "Obrigações legais": "receipt", "Outros": "tag", "Renda": "money", "Saúde": "heartbeat",
        "Saúde e bem-estar": "heartbeat", "Seguros": "shield-check", "Serviços": "wrench", "Serviços automotivos": "car",
        "Serviços de utilidade pública": "lightning", "Serviços digitais": "device-mobile", "Supermercado": "shopping-cart",
        "Taxas bancárias": "coins", "Transferência mesma titularidade": "arrows-left-right", "Transferências": "arrows-left-right",
        "Transporte": "bus", "Viagens": "airplane", "Educação": "graduation-cap", "Pets": "paw-print",
        "Telecomunicações": "phone", "Credit card payment": "credit-card", "Pagamento de fatura": "credit-card",
    ]
    static func name(for category: String) -> String { map[category] ?? "tag" }
}
