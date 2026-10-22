import SwiftUI
import SwiftData

/// Five views over the same cached data: Overview, Transactions, Cards, Investments, Rules.
struct FinancePage: View {
    let finance: Finance
    @Environment(UI.self) private var ui
    @Environment(\.modelContext) private var context
    @State private var tab = Tab.overview
    @State private var rules: [FinanceRule] = []
    @State private var budgets: [Budget] = []
    @State private var monthOffset = 0
    @State private var query = ""
    @State private var accountFilter: String?
    @State private var categoryFilter: String?

    enum Tab: String, CaseIterable { case overview = "Overview", transactions = "Transactions", cards = "Cards", investments = "Investments", rules = "Rules" }

    private var shown: [Shown] { finance.snapshot.shown(rules) }
    private var currentMonth: DateInterval { finance.month(monthOffset) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Finances").rise()
            Heading(muted: headingMuted, strong: headingStrong).padding(.top, 20).rise(0.05)

            HStack(spacing: 8) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button { tab = t } label: { Chip(text: t.rawValue, selected: tab == t) }.buttonStyle(PressStyle())
                }
                Spacer()
                if finance.loading { Spinner() } else if let fetched = finance.fetched {
                    Text("updated \(fetched, format: .relative(presentation: .named))").font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.4))
                }
            }
            .padding(.top, 36).rise(0.1)

            if !finance.hasKey {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Banco MCP key needed.").font(.wave(20, .medium)).tracking(-0.5)
                    Text("Open Settings (⌘,) and paste the sk_live key from app.mcp.ai. Wave only reads balances and transactions.")
                        .foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(4)
                }
                .padding(32).frame(maxWidth: 520, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
                .padding(.top, 48).rise(0.15)
            } else {
                if let error = finance.error { Text(error).font(.wave(14)).foregroundStyle(Theme.danger).padding(.top, 16) }
                Group {
                    switch tab {
                    case .overview: overview
                    case .transactions: transactionsTab
                    case .cards: cards
                    case .investments: investments
                    case .rules: rulesTab
                    }
                }
                .id(tab)
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in reload() }
        .task {
            finance.load()
            if finance.hasKey, finance.fetched.map({ Date.now.timeIntervalSince($0) > 3600 }) ?? true { await finance.refresh() }
        }
    }

    private func reload() {
        rules = FinanceRule.all(context)
        budgets = Budget.all(context)
    }

    private var headingMuted: String {
        switch tab {
        case .overview: "Where the money is."
        case .transactions: currentMonth.start.formatted(.dateTime.month(.wide).year()) + "."
        case .cards: "What the card owes."
        case .investments: "What the money earns."
        case .rules: "How things are named and filed."
        }
    }

    private var headingStrong: String {
        let t = finance.totals(shown, in: finance.month())
        switch tab {
        case .overview:
            let worth = finance.snapshot.worth.last?.total ?? 0
            return "\(worth.formatted(.currency(code: "BRL"))) net worth."
        case .transactions:
            let m = finance.totals(shown, in: currentMonth)
            return "\(m.income.formatted(.currency(code: "BRL"))) in, \(m.spent.formatted(.currency(code: "BRL"))) out."
        case .cards:
            let bill = finance.snapshot.bills.first?.total ?? 0
            return bill == 0 ? "No open bill." : "\(bill.formatted(.currency(code: "BRL"))) on the latest bill."
        case .investments:
            let net = finance.snapshot.investments.reduce(Decimal(0)) { $0 + $1.net }
            return "\(net.formatted(.currency(code: "BRL"))) invested."
        case .rules:
            return "\(rules.count) rule\(rules.count == 1 ? "" : "s"), \(t.spent == 0 ? "nothing" : "") counted this month."
                .replacingOccurrences(of: ", nothing counted this month.", with: ".")
        }
    }

    // MARK: Overview

    private var overview: some View {
        let month = finance.month(), last = finance.month(-1)
        let now = finance.totals(shown, in: month), before = finance.totals(shown, in: last)
        let categories = finance.byCategory(shown, in: month)
        let top = categories.first?.amount ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            DarkSection {
                VStack(alignment: .leading, spacing: 28) {
                    Eyebrow(text: "Accounts", onDark: true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: finance.stripe == nil ? 2 : 3), spacing: 16) {
                        ForEach(finance.accounts) { AccountCard(account: $0) }
                        if let stripe = finance.stripe { StripeCard(stripe: stripe) }
                    }
                }
            }
            .padding(.top, 40).rise(0.15)

            HStack(spacing: 16) {
                KPI(title: "In this month", value: now.income, previous: before.income, upIsGood: true)
                KPI(title: "Out this month", value: now.spent, previous: before.spent, upIsGood: false)
                KPI(title: "Left", value: now.income - now.spent, previous: before.income - before.spent, upIsGood: true)
            }
            .padding(.top, 16).rise(0.2)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        Text("Twelve months").font(.wave(20, .medium)).tracking(-0.5)
                        Spacer()
                        legend(Theme.brand, "In")
                        legend(Theme.ink, "Out")
                    }
                    BarPairsChart(data: finance.trend(shown)).frame(height: 180)
                }
                .padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))

                VStack(alignment: .leading, spacing: 16) {
                    Text("Net worth").font(.wave(20, .medium)).tracking(-0.5)
                    if finance.snapshot.worth.count >= 2 {
                        LineChart(points: finance.snapshot.worth.map { ($0.date, $0.total) }).frame(height: 180)
                    } else {
                        Text("One point a day. Come back tomorrow for a line.").foregroundStyle(Theme.ink.opacity(0.5)).frame(height: 180)
                    }
                }
                .padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
            }
            .padding(.top, 16).rise(0.25)

            if !categories.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(text: "Spending by category")
                    Spacer()
                    Text("this month · budgets in red when passed").font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.4))
                }
                .padding(.top, 72).rise(0.3)
                VStack(spacing: 12) {
                    ForEach(Array(categories.prefix(10).enumerated()), id: \.element.name) { i, c in
                        let budget = budgets.first { $0.category == c.name }
                        CategoryBudgetRow(name: c.name, amount: c.amount, budget: budget.map { Decimal($0.limit) },
                                          share: budget.map { Double(truncating: (c.amount / Decimal($0.limit)) as NSNumber) } ?? Double(truncating: (c.amount / top) as NSNumber)) {
                            ui.open(.budget(c.name))
                        }
                        .rise(0.3 + Double(i) * 0.03)
                    }
                }
                .padding(.top, 24)
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text).font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.6))
        }
    }

    // MARK: Transactions

    private var filtered: [Shown] {
        shown.filter { r in
            currentMonth.contains(r.date)
                && (accountFilter == nil || r.raw.accountId == accountFilter)
                && (categoryFilter == nil || r.category == categoryFilter)
                && (query.isEmpty || r.title.localizedCaseInsensitiveContains(query) || r.raw.description.localizedCaseInsensitiveContains(query))
        }
    }

    private var transactionsTab: some View {
        let rows = filtered
        let days = Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
        let categoriesHere = Array(Set(shown.filter { currentMonth.contains($0.date) }.map(\.category))).sorted()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<12, id: \.self) { i in
                    let m = finance.month(-i)
                    Button { monthOffset = -i } label: { Chip(text: m.start.formatted(.dateTime.month(.abbreviated)), selected: monthOffset == -i) }.buttonStyle(PressStyle())
                }
            }
            .padding(.top, 32).rise(0.15)
            HStack(spacing: 8) {
                Button { accountFilter = nil } label: { Chip(text: "All accounts", selected: accountFilter == nil) }.buttonStyle(PressStyle())
                ForEach(finance.accounts) { a in
                    Button { accountFilter = a.id } label: { Chip(text: a.title.capitalized, selected: accountFilter == a.id) }.buttonStyle(PressStyle())
                }
                Spacer()
                HStack(spacing: 10) {
                    Icon("magnifying-glass", size: 14, color: Theme.ink.opacity(0.5))
                    TextField("Search", text: $query).textFieldStyle(.plain).font(.wave(14))
                }
                .padding(.horizontal, 16).padding(.vertical, 9).frame(width: 260)
                .background(Theme.paper.opacity(0.6), in: Capsule()).overlay(Capsule().stroke(Theme.ink.opacity(0.1)))
            }
            .padding(.top, 12).rise(0.2)
            if !categoriesHere.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        Button { categoryFilter = nil } label: { Chip(text: "All categories", selected: categoryFilter == nil) }.buttonStyle(PressStyle())
                        ForEach(categoriesHere, id: \.self) { c in
                            Button { categoryFilter = categoryFilter == c ? nil : c } label: { Chip(text: c, selected: categoryFilter == c) }.buttonStyle(PressStyle())
                        }
                    }
                }
                .scrollIndicators(.never)
                .padding(.top, 12).rise(0.25)
            }

            if rows.isEmpty {
                Text("Nothing here.").foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 48)
            }
            ForEach(days, id: \.key) { day, items in
                HStack(alignment: .firstTextBaseline) {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.wave(14, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
                    Spacer()
                    let net = items.filter { !$0.ignored }.reduce(Decimal(0)) { $0 + $1.value }
                    Text(net, format: .currency(code: "BRL")).font(.wave(14)).monospacedDigit().foregroundStyle(Theme.ink.opacity(0.5))
                }
                .padding(.top, 32).padding(.bottom, 12)
                VStack(spacing: 8) {
                    ForEach(items) { r in ShownRow(row: r) { ui.open(.transaction(r)) } }
                }
            }
        }
    }

    // MARK: Cards

    private var cards: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(finance.accounts.filter { $0.type == "CREDIT" }) { account in
                let bills = finance.snapshot.bills.filter { $0.accountId == account.id }
                let charges = shown.filter { $0.raw.accountId == account.id && finance.month().contains($0.date) }
                VStack(alignment: .leading, spacing: 0) {
                    DarkSection {
                        VStack(alignment: .leading, spacing: 28) {
                            Eyebrow(text: account.title.capitalized, onDark: true)
                            HStack(alignment: .top, spacing: 16) {
                                AccountCard(account: account)
                                if let bill = bills.first {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("Latest bill").font(.wave(20, .medium)).tracking(-0.5).foregroundStyle(Theme.paper)
                                        Text("closed \(bill.billClosingDate?.formatted(.dateTime.day().month(.abbreviated)) ?? "—") · due \(bill.dueDate.formatted(.dateTime.day().month(.abbreviated)))")
                                            .foregroundStyle(Theme.paper.opacity(0.5)).padding(.top, 4)
                                        Text(bill.total, format: .currency(code: "BRL")).font(.wave(36, .medium)).tracking(-0.9).monospacedDigit().foregroundStyle(Theme.paper).padding(.top, 24)
                                        Text("minimum \(bill.minimum.formatted(.currency(code: "BRL")))").foregroundStyle(Theme.paper.opacity(0.5)).padding(.top, 8)
                                    }
                                    .padding(32).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.darkCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.paper.opacity(0.06)))
                                }
                            }
                        }
                    }
                    .padding(.top, 40).rise(0.15)

                    if bills.count > 1 {
                        Eyebrow(text: "Past bills").padding(.top, 56).rise(0.2)
                        VStack(spacing: 8) {
                            ForEach(bills.dropFirst()) { b in
                                HStack {
                                    Text(b.dueDate.formatted(.dateTime.month(.wide).year())).font(.wave(18, .medium)).tracking(-0.4)
                                    Spacer()
                                    Text("due \(b.dueDate.formatted(.dateTime.day().month(.abbreviated)))").foregroundStyle(Theme.ink.opacity(0.5))
                                    Text(b.total, format: .currency(code: "BRL")).font(.wave(18, .medium)).monospacedDigit().frame(width: 150, alignment: .trailing)
                                }
                                .padding(.horizontal, 32).padding(.vertical, 14)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                            }
                        }
                        .padding(.top, 20)
                    }

                    Eyebrow(text: "Charges this month").padding(.top, 56).rise(0.25)
                    VStack(spacing: 8) {
                        if charges.isEmpty { Text("Nothing yet.").foregroundStyle(Theme.ink.opacity(0.5)) }
                        ForEach(charges.prefix(40)) { r in ShownRow(row: r) { ui.open(.transaction(r)) } }
                    }
                    .padding(.top, 20)
                }
            }
            if !finance.accounts.contains(where: { $0.type == "CREDIT" }) {
                Text("No credit card on this connection.").foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 48)
            }
        }
    }

    // MARK: Investments

    private var investments: some View {
        let list = finance.snapshot.investments
        let invested = list.reduce(Decimal(0)) { $0 + $1.invested }
        let net = list.reduce(Decimal(0)) { $0 + $1.net }
        let gross = list.reduce(Decimal(0)) { $0 + $1.current }
        let worth = finance.snapshot.worth
        let monthStart = finance.month().start
        let monthDelta: Decimal? = worth.first(where: { $0.date >= monthStart }).map { net - $0.investments }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                KPI(title: "Invested", value: invested, previous: nil, upIsGood: true)
                KPI(title: "Net yield", value: net - invested, previous: nil, upIsGood: true,
                    detail: invested == 0 ? nil : (Double(truncating: ((net - invested) / invested) as NSNumber)).formatted(.percent.precision(.fractionLength(2))))
                KPI(title: "Gross yield", value: gross - invested, previous: nil, upIsGood: true, detail: "taxes \((gross - net).formatted(.currency(code: "BRL")))")
                KPI(title: "This month", value: monthDelta ?? 0, previous: nil, upIsGood: true, detail: monthDelta == nil ? "first point today" : nil)
            }
            .padding(.top, 40).rise(0.15)

            if worth.count >= 2 {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Invested over time").font(.wave(20, .medium)).tracking(-0.5)
                    LineChart(points: worth.map { ($0.date, $0.investments) }).frame(height: 180)
                }
                .padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
                .padding(.top, 16).rise(0.2)
            }

            Eyebrow(text: "Positions").padding(.top, 56).rise(0.25)
            VStack(spacing: 12) {
                if list.isEmpty { Text("No investments on this connection.").foregroundStyle(Theme.ink.opacity(0.5)) }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, inv in
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inv.name.capitalized).font(.wave(18, .medium)).tracking(-0.4).lineLimit(1)
                            Text([inv.subtype, inv.rate.map { "\($0.formatted(.number.precision(.fractionLength(0))))% \(inv.rateType ?? "")" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5))
                        }
                        Spacer()
                        Text(inv.net, format: .currency(code: inv.currencyCode)).font(.wave(18, .medium)).monospacedDigit()
                        Text((inv.netYield >= 0 ? "+" : "") + inv.netYield.formatted(.currency(code: inv.currencyCode)) + " · " + inv.yieldPercent.formatted(.number.precision(.fractionLength(2))) + "%")
                            .font(.wave(14, .medium)).foregroundStyle(inv.netYield >= 0 ? Theme.brand : Theme.danger)
                            .frame(width: 190, alignment: .trailing)
                    }
                    .padding(.horizontal, 32).padding(.vertical, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                    .rise(0.25 + Double(i) * 0.04)
                }
            }
            .padding(.top, 20)
        }
    }

    // MARK: Rules

    private var rulesTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("A rule matches any transaction whose description contains the text. It can rename it, file it under a category, or leave it out of the totals. Rules apply to the whole year of history.")
                    .foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(4).frame(maxWidth: 640, alignment: .leading)
                Spacer()
                PrimaryButton(title: "New rule", icon: "plus") { ui.open(.rule(nil)) }
            }
            .padding(.top, 32).rise(0.15)
            VStack(spacing: 8) {
                if rules.isEmpty { Text("No rules yet.").foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 24) }
                ForEach(rules) { rule in
                    HStack(spacing: 16) {
                        Text("“\(rule.match)”").font(.wave(18, .medium)).tracking(-0.4).lineLimit(1)
                        Icon("arrow-right", size: 14, color: Theme.ink.opacity(0.4))
                        if !rule.rename.isEmpty { Chip(text: rule.rename) }
                        if !rule.category.isEmpty { Chip(text: rule.category, selected: true) }
                        if rule.ignore { Chip(text: "ignored", tint: Theme.danger) }
                        Spacer()
                        Text("\(shown.filter { $0.raw.description.localizedCaseInsensitiveContains(rule.match) }.count) matches").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5))
                        MenuButton(items: [
                            ("Edit", false, { ui.open(.rule(rule)) }),
                            ("Delete", true, { context.delete(rule); try? context.save() }),
                        ])
                    }
                    .padding(.horizontal, 32).padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
            }
            .padding(.top, 24).rise(0.2)

            if !budgets.isEmpty {
                Eyebrow(text: "Budgets").padding(.top, 56).rise(0.25)
                VStack(spacing: 8) {
                    ForEach(budgets) { b in
                        HStack {
                            Text(b.category).font(.wave(18, .medium)).tracking(-0.4)
                            Spacer()
                            Text(Decimal(b.limit), format: .currency(code: "BRL")).font(.wave(18, .medium)).monospacedDigit()
                            MenuButton(items: [
                                ("Edit", false, { ui.open(.budget(b.category)) }),
                                ("Delete", true, { context.delete(b); try? context.save() }),
                            ])
                        }
                        .padding(.horizontal, 32).padding(.vertical, 12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                    }
                }
                .padding(.top, 20)
            }
        }
    }
}

/// Big number with the change against last month.
struct KPI: View {
    let title: String
    let value: Decimal
    let previous: Decimal?
    let upIsGood: Bool
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5))
            Text(value, format: .currency(code: "BRL")).font(.wave(28, .medium)).tracking(-0.7).monospacedDigit()
            if let detail {
                Text(detail).font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.5))
            } else if let previous, previous != 0 {
                let change = Double(truncating: ((value - previous) / previous) as NSNumber)
                let good = upIsGood ? change >= 0 : change <= 0
                Text((change >= 0 ? "+" : "") + change.formatted(.percent.precision(.fractionLength(0))) + " vs last month")
                    .font(.wave(13, .medium)).foregroundStyle(good ? Theme.brand : Theme.danger)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}

/// Category with its share bar; budget text and red when passed; click to set the budget.
struct CategoryBudgetRow: View {
    let name: String
    let amount: Decimal
    let budget: Decimal?
    let share: Double
    let setBudget: () -> Void

    var body: some View {
        let over = budget.map { amount > $0 } ?? false
        HStack(spacing: 24) {
            Text(name).font(.wave(18, .medium)).tracking(-0.4).lineLimit(1).frame(width: 220, alignment: .leading)
            ShareBar(share: share, over: over)
            Text(amount, format: .currency(code: "BRL")).font(.wave(18, .medium)).monospacedDigit().frame(width: 130, alignment: .trailing)
                .foregroundStyle(over ? Theme.danger : Theme.ink)
            Button(action: setBudget) {
                Chip(text: budget.map { "of \($0.formatted(.currency(code: "BRL")))" } ?? "Set budget", selected: budget != nil)
            }
            .buttonStyle(PressStyle())
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 32).padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
    }
}

/// Transaction row after the rules: name, category chip, account, amount; dim when ignored.
struct ShownRow: View {
    let row: Shown
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.wave(17, .medium)).tracking(-0.4).lineLimit(1)
                if row.title != row.raw.description {
                    Text(row.raw.description).font(.wave(12)).foregroundStyle(Theme.ink.opacity(0.4)).lineLimit(1)
                }
            }
            Chip(text: row.category)
            if row.ignored { Chip(text: "ignored", tint: Theme.danger) }
            Spacer()
            Text(row.raw.account ?? "").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5))
            Text(row.value, format: .currency(code: row.raw.currencyCode))
                .font(.wave(17, .medium)).monospacedDigit()
                .foregroundStyle(row.value < 0 ? Theme.ink : Theme.brand)
                .frame(width: 130, alignment: .trailing)
        }
        .opacity(row.ignored ? 0.45 : 1)
        .padding(.horizontal, 32).padding(.vertical, 12)
        .background(Theme.surface.opacity(hover ? 1.6 : 1), in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hover = $0 }
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

/// The process step card: `rounded-3xl border border-paper/[0.06] bg-[#121212] p-8`.
struct AccountCard: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(account.title.capitalized).font(.wave(20, .medium)).tracking(-0.5).foregroundStyle(Theme.paper)
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
    }
}

// MARK: - Editors

struct RuleEditor: View {
    let rule: FinanceRule?
    let finance: Finance
    var prefill = ""
    @Environment(UI.self) private var ui
    @Environment(\.modelContext) private var context
    @State private var match = ""
    @State private var rename = ""
    @State private var category = ""
    @State private var ignore = false

    var body: some View {
        let groups = Array(Set(finance.snapshot.transactions.map { finance.snapshot.group(for: $0) })).sorted()
        FitScroll(max: 760) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PanelTitle(text: rule == nil ? "New rule" : "Edit rule")
                    Spacer()
                    if let rule { HoldButton(compact: true) { context.delete(rule); try? context.save(); ui.close() } }
                }
                VStack(spacing: 8) {
                    TextField("When the description contains…", text: $match).waveField()
                    TextField("Show it as (leave empty to keep the name)", text: $rename).waveField()
                    Select(title: "Category", value: $category, options: [("", "Keep the bank's")] + groups.map { ($0, $0) })
                    Switch(title: "Leave out of the totals", isOn: $ignore)
                }
                Text("\(finance.snapshot.transactions.filter { !match.isEmpty && $0.description.localizedCaseInsensitiveContains(match) }.count) transactions match today.")
                    .font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.5))
                PanelButtons(primary: rule == nil ? "Add rule" : "Save", disabled: match.trimmingCharacters(in: .whitespaces).isEmpty, action: save)
            }
        }
        .panel(width: 480)
        .onAppear {
            if let rule { match = rule.match; rename = rule.rename; category = rule.category; ignore = rule.ignore } else { match = prefill }
        }
    }

    private func save() {
        let r = rule ?? FinanceRule(match: match)
        r.match = match.trimmingCharacters(in: .whitespaces)
        r.rename = rename.trimmingCharacters(in: .whitespaces)
        r.category = category
        r.ignore = ignore
        if rule == nil { context.insert(r) }
        try? context.save()
        ui.close()
    }
}

struct TransactionDetail: View {
    let shown: Shown
    let finance: Finance
    @Environment(UI.self) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelTitle(text: shown.title)
            Text(shown.value, format: .currency(code: shown.raw.currencyCode)).font(.wave(36, .medium)).tracking(-0.9).monospacedDigit()
                .foregroundStyle(shown.value < 0 ? Theme.ink : Theme.brand)
            VStack(alignment: .leading, spacing: 8) {
                line("Bank says", shown.raw.description)
                line("Category", shown.category + (shown.raw.category.map { " · bank: \($0)" } ?? ""))
                line("Account", shown.raw.account ?? "")
                line("When", shown.date.formatted(date: .long, time: .shortened))
                if shown.ignored { line("Totals", "Left out by a rule") }
            }
            .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
            HStack {
                SecondaryButton(title: "Close") { ui.close() }
                Spacer()
                PrimaryButton(title: "Create rule from this") { ui.modal = .rule(nil); UI.shared.rulePrefill = shown.raw.description }
            }
            .padding(.top, 8)
        }
        .panel(width: 480)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5)).frame(width: 90, alignment: .leading)
            Text(value).font(.wave(14, .medium))
            Spacer()
        }
    }
}

struct BudgetEditor: View {
    let category: String
    @Environment(UI.self) private var ui
    @Environment(\.modelContext) private var context
    @State private var limit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelTitle(text: "Budget · \(category)")
            TextField("Monthly limit in R$", text: $limit).waveField()
            Text("The bar on the category turns red the month you pass it.").font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.5))
            PanelButtons(primary: "Save", disabled: Double(limit.replacingOccurrences(of: ",", with: ".")) == nil) {
                let value = Double(limit.replacingOccurrences(of: ",", with: ".")) ?? 0
                if let existing = Budget.all(context).first(where: { $0.category == category }) { existing.limit = value }
                else { context.insert(Budget(category: category, limit: value)) }
                try? context.save()
                ui.close()
            }
        }
        .panel(width: 440)
        .onAppear { if let b = Budget.all(context).first(where: { $0.category == category }) { limit = String(format: "%.0f", b.limit) } }
    }
}
