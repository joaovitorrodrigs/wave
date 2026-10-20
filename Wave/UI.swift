import SwiftUI
import EventKit
import SwiftData

/// App-wide navigation and modal state. One instance, reachable from menu commands and every view.
@Observable final class UI {
    static let shared = UI()
    var page: Page = .home
    var modal: Modal?

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
        case .notes: .newNote
        default: .newTask
        }
    }
}

enum Modal: Identifiable {
    case newTask, editTask(EKReminder), newHabit, editHabit(Habit), newNote, settings, palette

    var id: String {
        switch self {
        case .newTask: "newTask"
        case .editTask(let r): "task-\(r.calendarItemIdentifier)"
        case .newHabit: "newHabit"
        case .editHabit(let h): "habit-\(h.persistentModelID)"
        case .newNote: "newNote"
        case .settings: "settings"
        case .palette: "palette"
        }
    }
}

/// Dimmed canvas with the panel on top; the site's modal, not a sheet window.
struct ModalHost: View {
    let store: Store
    let notes: Notes
    let finance: Finance
    @Environment(UI.self) private var ui

    var body: some View {
        ZStack {
            if let modal = ui.modal {
                Theme.ink.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { ui.close() }
                    .transition(.opacity)
                panel(modal)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                Button("") { ui.close() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            }
        }
    }

    @ViewBuilder private func panel(_ modal: Modal) -> some View {
        switch modal {
        case .newTask: TaskEditor(store: store, reminder: nil)
        case .editTask(let r): TaskEditor(store: store, reminder: r)
        case .newHabit: HabitEditor(habit: nil)
        case .editHabit(let h): HabitEditor(habit: h)
        case .newNote: NoteEditor(notes: notes)
        case .settings: SettingsPanel()
        case .palette: Palette(store: store, notes: notes)
        }
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
            .shadow(color: Theme.ink.opacity(0.25), radius: 16, x: 16, y: 24)
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
