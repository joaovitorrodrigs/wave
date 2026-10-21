import WidgetKit
import SwiftUI
import AppIntents

struct TasksEntry: TimelineEntry {
    let date: Date
    let tasks: TasksSnapshot
}

struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry { TasksEntry(date: .now, tasks: TasksSnapshot(todos: [], reminders: [])) }
    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) { completion(TasksEntry(date: .now, tasks: TasksBridge.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        completion(Timeline(entries: [TasksEntry(date: .now, tasks: TasksBridge.load())], policy: .after(midnight)))
    }
}

enum TasksBridge {
    static func load() -> TasksSnapshot {
        guard let data = try? Data(contentsOf: Bridge.dir.appending(path: "tasks.json")) else { return TasksSnapshot(todos: [], reminders: []) }
        return (try? Bridge.decoder.decode(TasksSnapshot.self, from: data)) ?? TasksSnapshot(todos: [], reminders: [])
    }
    static func save(_ s: TasksSnapshot) {
        if let data = try? Bridge.encoder.encode(s) { try? data.write(to: Bridge.dir.appending(path: "tasks.json"), options: .atomic) }
    }
    static func queue(_ check: TodoCheck) {
        let url = Bridge.dir.appending(path: "checks.json")
        var list = (try? Data(contentsOf: url)).flatMap { try? Bridge.decoder.decode([TodoCheck].self, from: $0) } ?? []
        list.append(check)
        if let data = try? Bridge.encoder.encode(list) { try? data.write(to: url, options: .atomic) }
    }
}

struct CheckTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Task"
    @Parameter(title: "Task") var id: Double
    init() {}
    init(id: Double) { self.id = id }
    func perform() async throws -> some IntentResult {
        var s = TasksBridge.load()
        s.todos.removeAll { $0.id == id }
        TasksBridge.save(s)
        TasksBridge.queue(TodoCheck(id: id, at: .now))
        WidgetCenter.shared.reloadTimelines(ofKind: "tasks")
        return .result()
    }
}

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tasks", provider: TasksProvider()) { entry in
            TasksView(entry: entry).containerBackground(for: .widget) { WidgetTheme.canvas }
        }
        .configurationDisplayName("Tasks")
        .description("Your to-do list. Tap a circle to check it off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TasksView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = WidgetTheme(dark: scheme == .dark)
        let todos = entry.tasks.todos
        let limit = family == .systemSmall ? 3 : family == .systemMedium ? 5 : 10
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            if family == .systemSmall {
                Text("\(todos.count) to do").font(.custom("Instrument Sans", size: 22).weight(.medium)).foregroundStyle(theme.ink)
                ForEach(todos.prefix(limit)) { t in
                    HStack(spacing: 6) {
                        Circle().strokeBorder(theme.ink.opacity(0.3), lineWidth: 1.2).frame(width: 10, height: 10)
                        Text(t.title).font(.custom("Instrument Sans", size: 12)).foregroundStyle(theme.ink).lineLimit(1)
                    }
                }
            } else {
                HStack {
                    Text("To do").font(.custom("Instrument Sans", size: 13).weight(.medium)).foregroundStyle(theme.ink.opacity(0.6))
                    Spacer()
                    Text("\(todos.count)").font(.custom("Instrument Sans", size: 13)).foregroundStyle(theme.ink.opacity(0.4))
                }
                if todos.isEmpty {
                    Text("Nothing to do.").font(.custom("Instrument Sans", size: 13)).foregroundStyle(theme.ink.opacity(0.5))
                }
                ForEach(todos.prefix(limit)) { t in TodoWidgetRow(todo: t, theme: theme) }
                if todos.count > limit {
                    Text("+ \(todos.count - limit) more").font(.custom("Instrument Sans", size: 12)).foregroundStyle(theme.ink.opacity(0.4))
                }
                if family == .systemLarge, !entry.tasks.reminders.isEmpty {
                    Text("Reminders today").font(.custom("Instrument Sans", size: 13).weight(.medium)).foregroundStyle(theme.ink.opacity(0.6)).padding(.top, 6)
                    ForEach(entry.tasks.reminders.prefix(4)) { r in
                        HStack(spacing: 8) {
                            Text(r.title).font(.custom("Instrument Sans", size: 13)).foregroundStyle(theme.ink).lineLimit(1)
                            Spacer()
                            if let d = r.due { Text(d.formatted(date: .omitted, time: .shortened)).font(.custom("Instrument Sans", size: 11)).foregroundStyle(theme.ink.opacity(0.5)) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The app's row, shrunk: circle button, title, date on the right.
struct TodoWidgetRow: View {
    let todo: TodoSnapshot
    let theme: WidgetTheme
    var body: some View {
        let overdue = todo.due.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false
        HStack(spacing: 10) {
            Button(intent: CheckTodoIntent(id: todo.id)) {
                Circle().strokeBorder(theme.ink.opacity(0.3), lineWidth: 1.5).frame(width: 16, height: 16).contentShape(Circle())
            }
            .buttonStyle(.plain)
            Text(todo.title).font(.custom("Instrument Sans", size: 13).weight(.medium)).foregroundStyle(theme.ink).lineLimit(1)
            Spacer()
            if let due = todo.due {
                Text(Calendar.current.isDateInToday(due) ? "Today" : due.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.custom("Instrument Sans", size: 11))
                    .foregroundStyle(overdue ? Color(red: 0xDC / 255, green: 0x2F / 255, blue: 0x3A / 255) : theme.ink.opacity(0.5))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}
