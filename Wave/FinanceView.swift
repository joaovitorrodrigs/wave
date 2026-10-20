import SwiftUI

struct FinanceView: View {
    @State private var finance = Finance()

    var body: some View {
        List {
            Section("Accounts") {
                ForEach(finance.accounts) { a in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(a.title).font(.waveHeadline)
                            Text("\(a.subtype.replacingOccurrences(of: "_", with: " ").capitalized) · \(a.number)")
                                .font(.waveCaption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(a.value, format: .currency(code: a.currencyCode)).font(.waveTitle3).monospacedDigit()
                            if let c = a.creditData {
                                Text("bill due \(c.balanceDueDate ?? "?") · available \(Decimal(string: c.availableCreditLimit ?? "") ?? 0, format: .currency(code: a.currencyCode))")
                                    .font(.waveCaption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section("Last 30 days") {
                ForEach(finance.transactions) { t in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(t.description)
                            Text("\(t.date.formatted(date: .abbreviated, time: .omitted)) · \(t.category ?? "Uncategorized") · \(t.account ?? "")")
                                .font(.waveCaption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(t.value, format: .currency(code: t.currencyCode)).monospacedDigit()
                            .foregroundStyle(t.value < 0 ? .primary : Color.green)
                    }
                }
            }
        }
                .scrollContentBackground(.hidden)
        .toolbar {
            if let error = finance.error, !finance.accounts.isEmpty {
                Text(error).font(.waveCaption).foregroundStyle(.red).lineLimit(1)
            }
            if let fetched = finance.fetched {
                Text("updated \(fetched, format: .relative(presentation: .named))").font(.waveCaption).foregroundStyle(.secondary)
            }
            if finance.loading { ProgressView().controlSize(.small) }
            Button { Task { await finance.refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(finance.loading)
        }
        .overlay {
            if !finance.hasKey {
                ContentUnavailableView("Banco MCP key needed", systemImage: "key",
                    description: Text("Open Settings (⌘,) and paste the sk_live key from app.mcp.ai."))
            } else if let error = finance.error, finance.accounts.isEmpty {
                ContentUnavailableView("Can't reach Banco MCP", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
        .task {
            finance.load()
            if finance.fetched.map({ Date.now.timeIntervalSince($0) > 3600 }) ?? true { await finance.refresh() }
        }
    }
}

struct SettingsView: View {
    @State private var key = Keychain.get(Finance.keyAccount) ?? ""

    var body: some View {
        Form {
            SecureField("Banco MCP API key", text: $key, prompt: Text("sk_live_…"))
            Text("Read-only access to your bank accounts through Banco MCP (Open Finance Brasil). Kept in the macOS Keychain.")
                .font(.waveCaption).foregroundStyle(.secondary)
            Link("Create a key at app.mcp.ai", destination: URL(string: "https://app.mcp.ai/settings/api-keys")!)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onChange(of: key) { Keychain.set(key, account: Finance.keyAccount) }
    }
}
