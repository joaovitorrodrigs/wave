import SwiftData
import Foundation

/// Wave's own to-do: things to get done, checked off and gone. Not a Reminder: no alert, no repeat, no Apple sync.
@Model final class Todo {
    var title: String
    var note: String
    var due: Date?
    var done: Date?
    var created = Date.now

    init(title: String, note: String = "", due: Date? = nil) {
        self.title = title
        self.note = note
        self.due = due
    }

    static func open(_ context: ModelContext) -> [Todo] {
        let d = FetchDescriptor<Todo>(predicate: #Predicate { $0.done == nil }, sortBy: [SortDescriptor(\.created)])
        return (try? context.fetch(d)) ?? []
    }

    /// Checked in the last 7 days, newest first; older ones are purged.
    static func recentlyDone(_ context: ModelContext) -> [Todo] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let d = FetchDescriptor<Todo>(predicate: #Predicate { $0.done != nil }, sortBy: [SortDescriptor(\.done, order: .reverse)])
        let all = (try? context.fetch(d)) ?? []
        for old in all where (old.done ?? .now) < cutoff { context.delete(old) }
        return all.filter { ($0.done ?? .now) >= cutoff }
    }
}
