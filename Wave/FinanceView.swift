import SwiftUI

struct FinancePage: View {
    let finance: Finance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Finances").rise()
            Heading(muted: "Where the money is.", strong: summary).padding(.top, 20).rise(0.05)

            if !finance.hasKey {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Banco MCP key needed.").font(.wave(20, .medium)).tracking(-0.5)
                    Text("Open Settings (⌘,) and paste the sk_live key from app.mcp.ai. Wave only reads balances and transactions.")
                        .foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(4)
                }
                .padding(32).frame(maxWidth: 520, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
                .padding(.top, 48).rise(0.1)
            } else {
                DarkSection {
                    VStack(alignment: .leading, spacing: 28) {
                        HStack(alignment: .firstTextBaseline) {
                            Eyebrow(text: "Accounts", onDark: true)
                            Spacer()
                            if finance.loading {
                                ProgressView().controlSize(.small).tint(Theme.paper)
                            } else if let fetched = finance.fetched {
                                Text("updated \(fetched, format: .relative(presentation: .named))").font(.wave(14)).foregroundStyle(Theme.paper.opacity(0.4))
                            }
                        }
                        if let error = finance.error {
                            Text(error).font(.wave(14)).foregroundStyle(Theme.paper.opacity(0.6))
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            ForEach(finance.accounts) { AccountCard(account: $0) }
                        }
                    }
                }
                .padding(.top, 48).rise(0.1)

                if !finance.transactions.isEmpty {
                    Eyebrow(text: "Last 30 days").padding(.top, 56).rise(0.15)
                    LazyVStack(spacing: 12) {
                        ForEach(Array(finance.transactions.enumerated()), id: \.element.id) { i, t in
                            TransactionRow(transaction: t).rise(0.2 + Double(min(i, 8)) * 0.04)
                        }
                    }
                    .padding(.top, 20)
                }
            }
        }
        .task {
            finance.load()
            if finance.hasKey, finance.fetched.map({ Date.now.timeIntervalSince($0) > 3600 }) ?? true { await finance.refresh() }
        }
    }

    private var summary: String {
        guard let checking = finance.accounts.first(where: { $0.type == "BANK" }) else { return "Connect a bank to see it here." }
        return "\(checking.value.formatted(.currency(code: checking.currencyCode))) in the account."
    }
}

/// The process step card: `rounded-3xl border border-paper/[0.06] bg-[#121212] p-8` with an inset top highlight.
struct AccountCard: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(account.title).font(.wave(20, .medium)).tracking(-0.5).foregroundStyle(Theme.paper)
            Text("\(account.subtype.replacingOccurrences(of: "_", with: " ").capitalized) · \(account.number)")
                .foregroundStyle(Theme.paper.opacity(0.5)).padding(.top, 4)
            Text(account.value, format: .currency(code: account.currencyCode))
                .font(.wave(36, .medium)).tracking(-0.9).monospacedDigit().foregroundStyle(Theme.paper).padding(.top, 24)
            if let c = account.creditData {
                Text("Bill due \(c.balanceDueDate ?? "?") · \((Decimal(string: c.availableCreditLimit ?? "") ?? 0).formatted(.currency(code: account.currencyCode))) available")
                    .foregroundStyle(Theme.paper.opacity(0.5)).padding(.top, 8)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.darkCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.paper.opacity(0.06)))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.paper.opacity(0.06), lineWidth: 1).mask(Rectangle().frame(height: 1).frame(maxHeight: .infinity, alignment: .top))
        }
    }
}

/// Experience row for a transaction; credits in brand green.
struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description).font(.wave(18, .medium)).tracking(-0.4).lineLimit(1)
                Text("\(transaction.category ?? "Uncategorized") · \(transaction.account ?? "")").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5))
            }
            Spacer()
            Text(transaction.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(Theme.ink.opacity(0.5))
            Text(transaction.value, format: .currency(code: transaction.currencyCode))
                .font(.wave(18, .medium)).monospacedDigit()
                .foregroundStyle(transaction.value < 0 ? Theme.ink : Theme.brand)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 32).padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
    }
}

struct SettingsView: View {
    @State private var key = Keychain.get(Finance.keyAccount) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Banco MCP").font(.wave(26, .medium)).tracking(-0.6)
            SecureField("sk_live_…", text: $key).waveField()
            Text("Read-only access to your bank accounts through Banco MCP (Open Finance Brasil). Kept in the macOS Keychain.")
                .font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(3)
            Link("Create a key at app.mcp.ai", destination: URL(string: "https://app.mcp.ai/settings/api-keys")!).font(.wave(14, .medium))
        }
        .padding(32)
        .frame(width: 480)
        .font(.wave(16))
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
        .preferredColorScheme(.light)
        .onChange(of: key) { Keychain.set(key, account: Finance.keyAccount) }
    }
}
