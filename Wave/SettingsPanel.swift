import SwiftUI
import SwiftData

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
            Text("Widgets").font(.wave(16, .medium)).padding(.top, 12)
            WidgetThemePicker()
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
            Text("Quick add from anywhere: ⌥Space. Siri: “Add a task in Wave”.").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).padding(.top, 12)
        }
        }
        .panel(width: 520)
        .onChange(of: key) { Keychain.set(key, account: Finance.keyAccount) }
        .onChange(of: stripe) { Keychain.set(stripe, account: Finance.stripeAccount) }
        .onChange(of: googleID) { Keychain.set(googleID, account: Gmail.clientAccount) }
        .onChange(of: googleSecret) { Keychain.set(googleSecret, account: Gmail.secretAccount) }
    }
}
