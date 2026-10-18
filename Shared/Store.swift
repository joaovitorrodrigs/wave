import EventKit
import Observation

enum Selection: Hashable {
    case today
    case habits
    case notes
    case list(EKCalendar)
}

@Observable final class Store {
    let ek = EKEventStore()
    var lists: [EKCalendar] = []
    var items: [EKReminder] = []
    var events: [EKEvent] = []
    var authorized = false
    var accessError: String?

    func load() async {
        do { authorized = try await ek.requestFullAccessToReminders() }
        catch { accessError = "\(error)" }
        lists = ek.calendars(for: .reminder).sorted { $0.title < $1.title }
    }

    func fetch(_ selection: Selection) async {
        let predicate: NSPredicate
        switch selection {
        case .today:
            predicate = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: Calendar.current.endOfToday, calendars: nil)
        case .list(let list):
            predicate = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        default:
            return
        }
        let found = await withCheckedContinuation { k in
            ek.fetchReminders(matching: predicate) { k.resume(returning: $0 ?? []) }
        }
        items = found.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func fetchEvents() async {
        guard (try? await ek.requestFullAccessToEvents()) == true else { return }
        let today = ek.predicateForEvents(withStart: Calendar.current.startOfDay(for: .now), end: Calendar.current.endOfToday, calendars: nil)
        events = ek.events(matching: today).sorted { $0.startDate < $1.startDate }
    }

    func add(_ title: String, to list: EKCalendar?, due: Date? = nil) throws {
        let r = EKReminder(eventStore: ek)
        r.title = title
        r.calendar = list ?? ek.defaultCalendarForNewReminders()
        r.dueDateComponents = due.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        try ek.save(r, commit: true)
    }

    func reminder(id: String) -> EKReminder? { ek.calendarItem(withIdentifier: id) as? EKReminder }

    func save(_ r: EKReminder) throws { try ek.save(r, commit: true) }
}

extension EKReminder: @retroactive Identifiable {
    public var id: String { calendarItemIdentifier }
    var dueDate: Date? { dueDateComponents.flatMap(Calendar.current.date(from:)) }
}

extension Calendar {
    var endOfToday: Date { date(byAdding: .day, value: 1, to: startOfDay(for: .now))! }
}
