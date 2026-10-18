import EventKit
import Observation

enum Selection: Hashable {
    case today
    case list(EKCalendar)
}

@Observable final class Reminders {
    let store = EKEventStore()
    var lists: [EKCalendar] = []
    var items: [EKReminder] = []
    var authorized = false
    var accessError: String?

    func load() async {
        do { authorized = try await store.requestFullAccessToReminders() }
        catch { accessError = "\(error)" }
        lists = store.calendars(for: .reminder).sorted { $0.title < $1.title }
    }

    func fetch(_ selection: Selection) async {
        let predicate = switch selection {
        case .today:
            store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: Calendar.current.endOfToday, calendars: nil)
        case .list(let list):
            store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        }
        let found = await withCheckedContinuation { k in
            store.fetchReminders(matching: predicate) { k.resume(returning: $0 ?? []) }
        }
        items = found.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func add(_ title: String, to list: EKCalendar?, due: Date? = nil) throws {
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = list ?? store.defaultCalendarForNewReminders()
        r.dueDateComponents = due.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        try store.save(r, commit: true)
    }

    func reminder(id: String) -> EKReminder? { store.calendarItem(withIdentifier: id) as? EKReminder }

    func save(_ r: EKReminder) throws { try store.save(r, commit: true) }
}

extension EKReminder: @retroactive Identifiable {
    public var id: String { calendarItemIdentifier }
    var dueDate: Date? { dueDateComponents.flatMap(Calendar.current.date(from:)) }
}

extension Calendar {
    var endOfToday: Date { date(byAdding: .day, value: 1, to: startOfDay(for: .now))! }
}
