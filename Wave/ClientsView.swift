import SwiftUI
import SwiftData
import EventKit

@Model final class Client {
    var name: String
    var created = Date.now
    init(name: String) { self.name = name }
}

/// One page per client: open tasks, coming events, notes and payments that carry the client's name.
struct ClientsPage: View {
    let store: Store
    let finance: Finance
    @Query(sort: \Client.name) private var clients: [Client]
    @Environment(UI.self) private var ui
    @Environment(\.modelContext) private var context
    @State private var selected: Client?
    @State private var tasks: [EKReminder] = []
    @State private var events: [EKEvent] = []
    @State private var notes = Notes()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Clients").rise()
            Heading(muted: "Who you are working with.", strong: clients.isEmpty ? "Nobody yet." : "\(clients.count) client\(clients.count == 1 ? "" : "s").")
                .padding(.top, 20).rise(0.05)

            if clients.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Add a client by name.").font(.wave(20, .medium)).tracking(-0.5)
                    Text("Wave then gathers every task, event, note and payment that mentions that name. A Reminders list with the same name counts too.")
                        .foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(4)
                    PrimaryButton(title: "New client", icon: "plus", large: true) { ui.open(.newClient) }
                }
                .padding(32).frame(maxWidth: 560, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
                .padding(.top, 48).rise(0.1)
            } else {
                HStack(spacing: 8) {
                    ForEach(clients) { c in
                        Button { selected = c } label: { Chip(text: c.name, selected: selected == c) }.buttonStyle(PressStyle())
                    }
                    Spacer()
                    if let selected {
                        MenuButton(items: [
                            ("Rename", false, { ui.open(.editClient(selected)) }),
                            ("Delete", true, { context.delete(selected); self.selected = nil }),
                        ])
                    }
                }
                .padding(.top, 36).rise(0.1)

                if let client = selected {
                    let money = finance.transactions.filter { $0.description.localizedCaseInsensitiveContains(client.name) }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading, spacing: 16) {
                        block("Tasks", count: tasks.count) {
                            ForEach(tasks.prefix(6)) { r in
                                row(r.title ?? "", detail: r.dueDate.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? r.calendar.title) { ui.open(.editTask(r)) }
                            }
                        }
                        block("Events", count: events.count) {
                            ForEach(events.prefix(6), id: \.self) { e in
                                row(e.title ?? "", detail: e.startDate.formatted(.dateTime.day().month(.abbreviated).hour().minute())) { ui.open(.editEvent(e)) }
                            }
                        }
                        block("Notes", count: notes.items.count) {
                            ForEach(notes.items.prefix(6)) { n in
                                row(n.title, detail: n.modified.formatted(.relative(presentation: .named))) { notes.open(n) }
                            }
                        }
                        block("Payments", count: money.count) {
                            let total = money.filter { $0.value > 0 }.reduce(Decimal(0)) { $0 + $1.value }
                            if total > 0 {
                                Text(total, format: .currency(code: "BRL")).font(.wave(28, .medium)).tracking(-0.7).padding(.horizontal, 16).padding(.top, 8)
                            }
                            ForEach(money.prefix(5)) { t in
                                row(t.description, detail: t.value.formatted(.currency(code: t.currencyCode))) {}
                            }
                        }
                    }
                    .padding(.top, 40).rise(0.15)
                    .task(id: client.persistentModelID) { await load(client) }
                }
            }
        }
        .onAppear { if selected == nil { selected = clients.first } }
        .onChange(of: clients.count) { if selected == nil || !clients.contains(where: { $0 == selected }) { selected = clients.first } }
    }

    private func block<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.wave(20, .medium)).tracking(-0.5)
                Spacer()
                Chip(text: "\(count)")
            }
            .padding(.horizontal, 20).padding(.vertical, 12).cardBlock()
            VStack(spacing: 4) {
                if count == 0 { Text("Nothing with this name.").foregroundStyle(Theme.ink.opacity(0.5)).padding(16) }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6).cardBlock()
        }
        .cardFrame()
    }

    private func row(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.wave(16, .medium)).lineLimit(1)
                Spacer()
                Text(detail).font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load(_ client: Client) async {
        let name = client.name
        tasks = await store.allOpen().filter { ($0.title ?? "").localizedCaseInsensitiveContains(name) || $0.calendar.title.localizedCaseInsensitiveCompare(name) == .orderedSame }
        let cal = Calendar.current
        events = await store.events(from: cal.date(byAdding: .day, value: -30, to: .now)!, to: cal.date(byAdding: .day, value: 90, to: .now)!)
            .filter { ($0.title ?? "").localizedCaseInsensitiveContains(name) }
        await notes.load(query: name)
    }
}

struct ClientEditor: View {
    let client: Client?
    @Environment(\.modelContext) private var context
    @Environment(UI.self) private var ui
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelTitle(text: client == nil ? "New client" : "Rename client")
            TextField("Client name", text: $name).waveField()
            Text("Tasks, events, notes and payments are matched by this name.").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6))
            PanelButtons(primary: "Save", disabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if let client { client.name = trimmed } else { context.insert(Client(name: trimmed)) }
                ui.close()
            }
        }
        .panel(width: 440)
        .onAppear { name = client?.name ?? "" }
    }
}
