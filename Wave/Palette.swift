import SwiftUI
import SwiftData
import EventKit

/// ⌘K: one field that finds pages, tasks, notes and habits, or creates a task from what you typed.
struct Palette: View {
    let store: Store
    let notes: Notes
    @Environment(UI.self) private var ui
    @Query(sort: \Habit.created) private var habits: [Habit]
    @State private var query = ""
    @State private var tasks: [EKReminder] = []
    @FocusState private var focused: Bool

    private enum Hit: Identifiable {
        case page(Page), task(EKReminder), note(Note), habit(Habit), create(String)
        var id: String {
            switch self {
            case .page(let p): "page-\(p.rawValue)"
            case .task(let r): "task-\(r.calendarItemIdentifier)"
            case .note(let n): "note-\(n.id)"
            case .habit(let h): "habit-\(h.persistentModelID)"
            case .create: "create"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Icon("magnifying-glass", size: 18, color: Theme.ink.opacity(0.5))
                TextField("Search pages, tasks, notes, habits. Return runs the first result.", text: $query)
                    .textFieldStyle(.plain).font(.wave(20, .medium)).focused($focused)
                    .onSubmit { if let first = hits.first { run(first) } }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))

            if !hits.isEmpty {
                VStack(spacing: 2) {
                    ForEach(hits) { hit in OptionRow(text: label(hit)) { run(hit) } }
                }
                .padding(6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
            }
        }
        .panel(width: 640)
        .task {
            focused = true
            tasks = await store.reminders(matching: store.ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil))
        }
    }

    private var hits: [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Page.allCases.map { .page($0) } }
        var out: [Hit] = Page.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(q) }.map { .page($0) }
        out += tasks.filter { ($0.title ?? "").localizedCaseInsensitiveContains(q) }.prefix(5).map { .task($0) }
        out += notes.items.filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(4).map { .note($0) }
        out += habits.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(3).map { .habit($0) }
        out.append(.create(q))
        return out
    }

    private func label(_ hit: Hit) -> String {
        switch hit {
        case .page(let p): p.rawValue
        case .task(let r): "Task · \(r.title ?? "")"
        case .note(let n): "Note · \(n.title)"
        case .habit(let h): "Habit · \(h.name)\(h.isDone(.now) ? " (done today, click to undo)" : " (mark today)")"
        case .create(let q): "Create task “\(q)”"
        }
    }

    private func run(_ hit: Hit) {
        switch hit {
        case .page(let p): ui.page = p; ui.close()
        case .task(let r): ui.modal = .editTask(r)
        case .note(let n): notes.open(n); ui.close()
        case .habit(let h): h.toggle(.now); ui.close()
        case .create(let q): try? store.add(q, to: nil); ui.close()
        }
    }
}
