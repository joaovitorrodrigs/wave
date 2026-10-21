import Foundation
import SwiftData
import AppKit
import WidgetKit

/// Keeps the widget's snapshot in step with the store, and folds the widget's toggles back in.
enum WidgetBridge {
    private static var watcher: DispatchSourceFileSystemObject?

    static func start() {
        sync()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in sync() }
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in write() }
        watch()
    }

    /// Apply the widget's toggles, then publish the current habits.
    static func sync() {
        let dir = HabitSnapshot.bridgeDirectory
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
        source.setEventHandler { if FileManager.default.fileExists(atPath: dir.appending(path: "toggles.json").path) { sync() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
