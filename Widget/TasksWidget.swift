import WidgetKit
import SwiftUI
import AppIntents

struct TasksEntry: TimelineEntry {
    let date: Date
    let tasks: TasksSnapshot
    var appearance: WidgetAppearance = .auto
}

struct TasksProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TasksEntry { TasksEntry(date: .now, tasks: TasksSnapshot(todos: [], reminders: [])) }
    func snapshot(for configuration: AppearanceIntent, in context: Context) async -> TasksEntry {
        TasksEntry(date: .now, tasks: TasksBridge.load(), appearance: configuration.appearance)
    }
    func timeline(for configuration: AppearanceIntent, in context: Context) async -> Timeline<TasksEntry> {
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        return Timeline(entries: [TasksEntry(date: .now, tasks: TasksBridge.load(), appearance: configuration.appearance)], policy: .after(midnight))
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
        WidgetCenter.shared.reloadTimelines(ofKind: "wave.tasks")
        return .result()
    }
}

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "wave.tasks", intent: AppearanceIntent.self, provider: TasksProvider()) { entry in
            TasksView(entry: entry).containerBackground(for: .widget) { WidgetCanvas(appearance: entry.appearance) }
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
        let theme = WidgetTheme.resolve(entry.appearance, scheme: scheme)
        let todos = entry.tasks.todos
        let limit = family == .systemSmall ? 3 : family == .systemMedium ? 5 : 10
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(todos.count)").font(.custom("Instrument Sans", size: family == .systemSmall ? 28 : 22).weight(.medium)).foregroundStyle(WidgetTheme.violet)
                Spacer()
                if todos.count > limit {
                    Text("+\(todos.count - limit)").font(.custom("Instrument Sans", size: 12)).foregroundStyle(theme.ink.opacity(0.4))
                }
            }
            if todos.isEmpty {
                PhIcon("check-circle", size: 22, color: WidgetTheme.violet)
            }
            ForEach(todos.prefix(limit)) { t in TodoWidgetRow(todo: t, theme: theme, compact: family == .systemSmall) }
            if family == .systemLarge, !entry.tasks.reminders.isEmpty {
                PhIcon("bell", size: 14, color: theme.ink.opacity(0.4)).padding(.top, 6)
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The app's row, shrunk: violet circle to check, title, date on the right.
struct TodoWidgetRow: View {
    let todo: TodoSnapshot
    let theme: WidgetTheme
    var compact = false
    var body: some View {
        let overdue = todo.due.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false
        HStack(spacing: compact ? 8 : 10) {
            Button(intent: CheckTodoIntent(id: todo.id)) {
                Circle().strokeBorder(WidgetTheme.violet, lineWidth: 1.5).frame(width: compact ? 12 : 16, height: compact ? 12 : 16).contentShape(Circle())
            }
            .buttonStyle(.plain)
            Text(todo.title).font(.custom("Instrument Sans", size: compact ? 12 : 13).weight(.medium)).foregroundStyle(theme.ink).lineLimit(1)
            Spacer()
            if let due = todo.due, !compact {
                Text(Calendar.current.isDateInToday(due) ? "Today" : due.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.custom("Instrument Sans", size: 11))
                    .foregroundStyle(overdue ? Color(red: 0xDC / 255, green: 0x2F / 255, blue: 0x3A / 255) : theme.ink.opacity(0.5))
            }
        }
        .padding(.horizontal, compact ? 0 : 12).padding(.vertical, compact ? 2 : 7)
        .background(compact ? Color.clear : theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}
