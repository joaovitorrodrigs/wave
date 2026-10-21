import Foundation
import SwiftData
import AppKit
import WidgetKit
import EventKit

/// Keeps the widget's snapshot in step with the store, and folds the widget's toggles back in.
enum WidgetBridge {
    private static var watcher: DispatchSourceFileSystemObject?

    static func start() {
        sync()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in sync() }
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in write(); Task { await writeTasks() } }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in Task { await writeEvents(); await writeTasks() } }
        Task { await writeEvents() }
        watch()
    }

    private static var ready: Bool { FileManager.default.fileExists(atPath: HabitSnapshot.bridgeDirectory.deletingLastPathComponent().path) }

    private static func put<T: Encodable>(_ value: T, as name: String, kind: String) {
        guard ready else { return }
        let dir = HabitSnapshot.bridgeDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? encoder.encode(value) {
            try? data.write(to: dir.appending(path: name), options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    static func writeLocation(_ location: LocationSnapshot) { put(location, as: "location.json", kind: "weather") }

    /// Open to-dos and today's reminders for the tasks widget.
    static func writeTasks() async {
        guard ready else { return }
        let context = ModelContext(Database.container)
        let todos = Todo.open(context).map { TodoSnapshot(id: $0.created.timeIntervalSinceReferenceDate, title: $0.title, due: $0.due) }
        let store = Store()
        await store.load()
        await store.fetch(.today)
        let reminders = store.items.map { ReminderSnapshot(title: $0.title ?? "", due: $0.dueDate) }
        put(TasksSnapshot(todos: todos, reminders: reminders), as: "tasks.json", kind: "tasks")
    }

    /// The next 45 days of events for the calendar widget.
    static func writeEvents() async {
        guard ready else { return }
        let store = Store()
        await store.load()
        let cal = Calendar.current
        let events = await store.events(from: cal.startOfDay(for: .now), to: cal.date(byAdding: .day, value: 45, to: .now)!)
        let snapshot = events.map { e in
            let c = e.calendar.cgColor.flatMap { NSColor(cgColor: $0) }?.usingColorSpace(.sRGB)
            let hex = c.map { String(format: "%02X%02X%02X", Int($0.redComponent * 255), Int($0.greenComponent * 255), Int($0.blueComponent * 255)) } ?? "7430F7"
            return EventSnapshot(title: e.title ?? "", start: e.startDate, end: e.endDate, allDay: e.isAllDay, color: hex)
        }
        put(snapshot, as: "events.json", kind: "calendar")
    }

    /// Apply the widget's toggles and checks, then publish habits and tasks.
    static func sync() {
        Task { await writeEvents(); await writeTasks() }
        let dir = HabitSnapshot.bridgeDirectory
        let checks = dir.appending(path: "checks.json")
        if let data = try? Data(contentsOf: checks), let list = try? decoder.decode([TodoCheck].self, from: data), !list.isEmpty {
            let context = ModelContext(Database.container)
            let todos = Todo.open(context)
            for c in list {
                if let todo = todos.first(where: { abs($0.created.timeIntervalSinceReferenceDate - c.id) < 0.001 }) { todo.done = c.at }
            }
            try? context.save()
            try? FileManager.default.removeItem(at: checks)
        }
        let toggles = dir.appending(path: "toggles.json")
        if let data = try? Data(contentsOf: toggles), let list = try? decoder.decode([HabitToggle].self, from: data), !list.isEmpty {
            let context = ModelContext(Database.container)
            let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            for t in list {
                guard let habit = habits.first(where: { abs($0.created.timeIntervalSinceReferenceDate - t.id) < 0.001 }) else { continue }
                habit.toggle(t.day)
            }
            try? context.save()
            try? FileManager.default.removeItem(at: toggles)
        }
        write()
        if watcher == nil { watch() }
    }

    static func write() {
        let dir = HabitSnapshot.bridgeDirectory
        guard FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().path) else { return }   // widget never ran
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let context = ModelContext(Database.container)
        let habits = (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.created)]))) ?? []
        let snapshot = habits.map { HabitSnapshot(id: $0.created.timeIntervalSinceReferenceDate, name: $0.name, icon: $0.icon, color: $0.color, days: $0.days) }
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: dir.appending(path: "habits.json"), options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: "habits")
        }
    }

    /// While the app runs, toggles from the widget land within a second.
    private static func watch() {
        let dir = HabitSnapshot.bridgeDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler {
            let fm = FileManager.default
            if fm.fileExists(atPath: dir.appending(path: "toggles.json").path) || fm.fileExists(atPath: dir.appending(path: "checks.json").path) { sync() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
