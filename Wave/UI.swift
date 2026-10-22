import SwiftUI
import EventKit
import SwiftData

/// App-wide navigation and modal state. One instance, reachable from menu commands and every view.
@Observable final class UI {
    static let shared = UI()
    var page: Page = .home
    var modal: Modal?
    var menu: MenuState?
    /// Notes page reads these: a note to select, or a request to create one.
    var noteToOpen: Note?
    var noteRequest = 0
    var rulePrefill = ""

    func openNote(_ note: Note) { noteToOpen = note; page = .notes }
    func requestNewNote() { page = .notes; noteRequest += 1 }

    /// Menus render in a window-level layer so rows below cannot cover them and leaving the row does not close them.
    func openMenu(_ items: [(String, Bool, () -> Void)], at anchor: CGRect) {
        withAnimation(.easeOut(duration: 0.15)) { menu = MenuState(items: items, anchor: anchor) }
    }

    func closeMenu() {
        withAnimation(.easeOut(duration: 0.12)) { menu = nil }
    }

    func open(_ modal: Modal) {
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.35)) { self.modal = modal }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.18)) { modal = nil }
    }

    /// What ⌘N means on the current page.
    var newItem: Modal {
        switch page {
        case .habits: .newHabit
        case .calendar: .newEvent(.now)
        case .clients: .newClient
        default: .newTask
        }
    }
}

struct MenuState {
    let items: [(String, Bool, () -> Void)]   // title, destructive, action
    let anchor: CGRect                        // the ⋯ button, in the window's coordinate space
}

enum Modal: Identifiable {
    case newTask, editTask(EKReminder), editTodo(Todo), newHabit, editHabit(Habit), settings, palette
    case newEvent(Date), editEvent(EKEvent), newClient, editClient(Client)
    case rule(FinanceRule?), transaction(Shown), budget(String)

    var id: String {
        switch self {
        case .newTask: "newTask"
        case .editTask(let r): "task-\(r.calendarItemIdentifier)"
        case .editTodo(let t): "todo-\(t.persistentModelID)"
        case .newHabit: "newHabit"
        case .editHabit(let h): "habit-\(h.persistentModelID)"
        case .settings: "settings"
        case .palette: "palette"
        case .newEvent(let d): "event-\(d.timeIntervalSince1970)"
        case .editEvent(let e): "event-\(e.eventIdentifier ?? "")"
        case .newClient: "newClient"
        case .editClient(let c): "client-\(c.persistentModelID)"
        case .rule(let r): "rule-\(r.map { "\($0.persistentModelID)" } ?? "new")"
        case .transaction(let t): "tx-\(t.id)"
        case .budget(let c): "budget-\(c)"
        }
    }
}

/// Dimmed canvas with the panel on top; the site's modal, not a sheet window.
struct ModalHost: View {
    let store: Store
    let finance: Finance
    @Environment(UI.self) private var ui

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let menu = ui.menu {
                Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture { ui.closeMenu() }
                VStack(spacing: 6) {
                    ForEach(Array(menu.items.enumerated()), id: \.offset) { _, item in
                        if item.1 {
                            HoldButton(title: "Hold to \(item.0.lowercased())", doneTitle: "Done", compact: true, fullWidth: true) { ui.closeMenu(); item.2() }
                        } else {
                            MenuPill(title: item.0, icon: ["Edit", "Rename"].contains(item.0) ? "pencil-simple" : nil) { ui.closeMenu(); item.2() }
                        }
                    }
                }
                .frame(width: max(196, min(320, CGFloat(menu.items.map(\.0.count).max() ?? 0) * 8 + 60)))
                .padding(6)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                .shadow(color: Theme.shadow.opacity(0.18), radius: 14, x: 6, y: 10)
                .offset(x: max(8, min(menu.anchor.minX, 1400)), y: menu.anchor.maxY + 6)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
            if let modal = ui.modal {
                Theme.ink.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { ui.close() }
                    .transition(.opacity)
                panel(modal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                Button("") { ui.close() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private func panel(_ modal: Modal) -> some View {
        switch modal {
        case .newTask: TaskEditor(store: store, reminder: nil)
        case .editTask(let r): TaskEditor(store: store, reminder: r)
        case .editTodo(let t): TodoEditor(todo: t)
        case .newHabit: HabitEditor(habit: nil)
        case .editHabit(let h): HabitEditor(habit: h)
        case .settings: SettingsPanel()
        case .palette: Palette(store: store)
        case .newEvent(let d): EventEditor(store: store, event: nil, day: d)
        case .editEvent(let e): EventEditor(store: store, event: e, day: e.startDate)
        case .newClient: ClientEditor(client: nil)
        case .editClient(let c): ClientEditor(client: c)
        case .rule(let r): RuleEditor(rule: r, finance: finance, prefill: ui.rulePrefill).onDisappear { ui.rulePrefill = "" }
        case .transaction(let t): TransactionDetail(shown: t, finance: finance)
        case .budget(let c): BudgetEditor(category: c)
        }
    }
}

/// Menu action shaped like the hold button next to it: 36pt pill, surface fill, icon and label centered.
struct MenuPill: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: 14) }
                Text(title).font(.wave(13, .medium))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(Theme.ink.opacity(hover ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// `rounded-[32px] bg-paper p-8` with the long shadow.
struct Panel: ViewModifier {
    let width: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(32)
            .frame(width: width)
            .font(.wave(16))
            .foregroundStyle(Theme.ink)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
            .shadow(color: Theme.shadow.opacity(0.25), radius: 16, x: 16, y: 24)
    }
}

extension View {
    func panel(width: CGFloat = 460) -> some View { modifier(Panel(width: width)) }
}

struct PanelTitle: View {
    let text: String
    var body: some View { Text(text).font(.wave(26, .medium)).tracking(-0.6) }
}

struct PanelButtons: View {
    let primary: String
    var disabled = false
    let action: () -> Void
    @Environment(UI.self) private var ui
    var body: some View {
        HStack {
            SecondaryButton(title: "Cancel") { ui.close() }
            Spacer()
            PrimaryButton(title: primary, action: action).disabled(disabled).opacity(disabled ? 0.4 : 1).keyboardShortcut(.defaultAction)
        }
        .padding(.top, 8)
    }
}
