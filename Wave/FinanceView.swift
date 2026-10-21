import SwiftUI
import SwiftData

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
                                Spinner(onDark: true)
                            } else if let fetched = finance.fetched {
                                Text("updated \(fetched, format: .relative(presentation: .named))").font(.wave(14)).foregroundStyle(Theme.paper.opacity(0.4))
                            }
                        }
                        if let error = finance.error {
                            Text(error).font(.wave(14)).foregroundStyle(Theme.paper.opacity(0.6))
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: finance.stripe == nil ? 2 : 3), spacing: 16) {
                            ForEach(finance.accounts) { AccountCard(account: $0) }
                            if let stripe = finance.stripe { StripeCard(stripe: stripe) }
                        }
                    }
                }
                .padding(.top, 48).rise(0.1)

                if !finance.categories.isEmpty {
                    let totals = finance.monthTotals()
                    Eyebrow(text: "Spending by category").padding(.top, 96).rise(0.15)
                    Heading(muted: "This month against last.",
                            strong: "\(totals.spent.formatted(.currency(code: "BRL"))) out, \(totals.income.formatted(.currency(code: "BRL"))) in.")
                        .padding(.top, 20).rise(0.2)
                    let top = finance.categories.first?.thisMonth ?? 1
                    VStack(spacing: 12) {
                        ForEach(Array(finance.categories.prefix(8).enumerated()), id: \.element.id) { i, c in
                            CategoryRow(category: c, share: top > 0 ? c.thisMonth / top : 0).rise(0.25 + Double(i) * 0.04)
                        }
                    }
                    .padding(.top, 36)
                }

                if !finance.transactions.isEmpty {
                    Eyebrow(text: "Last 60 days").padding(.top, 96).rise(0.15)
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

/// Dark card for the studio's Stripe account.
struct StripeCard: View {
    let stripe: StripeSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wave Studio").font(.wave(20, .medium)).tracking(-0.5).foregroundStyle(Theme.paper)
            Text("Stripe · revenue this month").foregroundStyle(Theme.paper.opacity(0.5)).padding(.top, 4)
            Text(stripe.monthRevenue, format: .currency(code: stripe.currency))
                .font(.wave(36, .medium)).tracking(-0.9).monospacedDigit().foregroundStyle(Theme.brand).padding(.top, 24)
            Text("\(stripe.available.formatted(.currency(code: stripe.currency))) available to pay out")
                .foregroundStyle(Theme.paper.opacity(0.5)).padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.darkCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.paper.opacity(0.06)))
    }
}

/// Experience row with a bar: category, share of the top category, this month, change against last month.
struct CategoryRow: View {
    let category: CategorySpend
    let share: Decimal
    var body: some View {
        let delta: Double? = category.lastMonth > 0
            ? (Double(truncating: (category.thisMonth - category.lastMonth) as NSNumber) / Double(truncating: category.lastMonth as NSNumber)) : nil
        HStack(spacing: 24) {
            Text(category.name).font(.wave(18, .medium)).tracking(-0.4).lineLimit(1).frame(width: 220, alignment: .leading)
            Capsule().fill(Theme.ink.opacity(0.08)).frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(Theme.ink).frame(width: g.size.width * CGFloat(truncating: share as NSNumber))
                    }
                }
            Text(category.thisMonth, format: .currency(code: "BRL")).font(.wave(18, .medium)).monospacedDigit().frame(width: 130, alignment: .trailing)
            Group {
                if let delta {
                    Text((delta >= 0 ? "+" : "") + delta.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(delta > 0 ? Theme.danger : Theme.brand)
                } else {
                    Text(category.lastMonth == 0 ? "new" : "—").foregroundStyle(Theme.ink.opacity(0.5))
                }
            }
            .font(.wave(14, .medium)).frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 32).padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
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

struct SettingsPanel: View {
    @State private var key = Keychain.get(Finance.keyAccount) ?? ""
    @State private var stripe = Keychain.get(Finance.stripeAccount) ?? ""
    @State private var googleID = Keychain.get(Gmail.clientAccount) ?? ""
    @State private var googleSecret = Keychain.get(Gmail.secretAccount) ?? ""
    @State private var gmail = Gmail.shared
    @State private var imported: String?
    @AppStorage("weatherCity") private var weatherCity = ""
    @AppStorage("homeAddress") private var homeAddress = ""
    @AppStorage("workAddress") private var workAddress = ""
    @Environment(\.modelContext) private var context

    var body: some View {
        FitScroll(max: 760) {
        VStack(alignment: .leading, spacing: 16) {
            PanelTitle(text: "Settings")
            Text("Appearance").font(.wave(16, .medium)).padding(.top, 8)
            ThemePicker()
            Text("Weather and commute").font(.wave(16, .medium)).padding(.top, 12)
            TextField("City, if location is off (e.g. Belo Horizonte)", text: $weatherCity).waveField()
            TextField("Home address", text: $homeAddress).waveField()
            TextField("Work address", text: $workAddress).waveField()
            Text("Weather from Open-Meteo. Commute by car from Apple Maps, home → work before noon, work → home after.")
                .font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(3)
            Text("Notes").font(.wave(16, .medium)).padding(.top, 12)
            HStack(spacing: 12) {
                SecondaryButton(title: "Import from Apple Notes") {
                    Task {
                        do { imported = "\(try await AppleNotesImport.run(into: context)) notes copied." }
                        catch { imported = error.localizedDescription }
                    }
                }
                if let imported { Text(imported).font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)) }
            }
            Text("Copies every note's title and text into Wave once. Apple Notes is left as it is.")
                .font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(3)
            Text("Banco MCP").font(.wave(16, .medium)).padding(.top, 12)
            SecureField("sk_live_…", text: $key).waveField()
            Text("Read-only access to your bank accounts through Banco MCP (Open Finance Brasil). Kept in the macOS Keychain.")
                .font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(3)
            Link("Create a key at app.mcp.ai", destination: URL(string: "https://app.mcp.ai/settings/api-keys")!).font(.wave(14, .medium))
            Text("Stripe").font(.wave(16, .medium)).padding(.top, 12)
            SecureField("rk_live_… (restricted key, read only)", text: $stripe).waveField()
            Text("Shows this month's revenue and the available balance on the Finances page. Make a restricted key with read access to Balance and Charges.")
                .font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(3)
            Text("Gmail").font(.wave(16, .medium)).padding(.top, 12)
            TextField("OAuth client ID (…apps.googleusercontent.com)", text: $googleID).waveField()
            SecureField("OAuth client secret", text: $googleSecret).waveField()
            Text("In Google Cloud, enable the Gmail API and create an OAuth client of type Desktop app. Wave only reads unread mail; the refresh token stays in your Keychain.")
                .font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(3)
            HStack(spacing: 12) {
                if gmail.connected {
                    Chip(text: "Connected", selected: true)
                    SecondaryButton(title: "Disconnect") { gmail.disconnect() }
                } else if gmail.connecting {
                    Spinner()
                    Text("Finish in the browser…").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6))
                } else {
                    PrimaryButton(title: "Connect Google account") { Task { await gmail.connect() } }
                        .disabled(!gmail.hasClient).opacity(gmail.hasClient ? 1 : 0.4)
                }
            }
            if let error = gmail.error { Text(error).font(.wave(13)).foregroundStyle(Theme.danger) }
            Text("Quick add from anywhere: ⌘⇧Space. Siri: “Add a task in Wave”.").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).padding(.top, 12)
        }
        }
        .panel(width: 520)
        .onChange(of: key) { Keychain.set(key, account: Finance.keyAccount) }
        .onChange(of: stripe) { Keychain.set(stripe, account: Finance.stripeAccount) }
        .onChange(of: googleID) { Keychain.set(googleID, account: Gmail.clientAccount) }
        .onChange(of: googleSecret) { Keychain.set(googleSecret, account: Gmail.secretAccount) }
    }
}
