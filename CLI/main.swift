import EventKit
import Foundation

// macOS attributes a CLI's privacy permissions to the app that launched it (Terminal, Cursor,
// Claude Code). Hosts without a Reminders usage string get a silent deny and no prompt.
// Re-spawn once with responsibility disclaimed so `wave` is its own TCC identity.
@_silgen_name("responsibility_spawnattrs_setdisclaim")
func responsibility_spawnattrs_setdisclaim(_ attrs: UnsafeMutablePointer<posix_spawnattr_t?>, _ disclaim: Int32) -> Int32

if getenv("WAVE_DISCLAIMED") == nil, let exe = Bundle.main.executablePath {
    var attrs: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attrs)
    _ = responsibility_spawnattrs_setdisclaim(&attrs, 1)
    setenv("WAVE_DISCLAIMED", "1", 1)
    var argv = CommandLine.arguments.map { strdup($0) }
    argv.append(nil)
    var pid: pid_t = 0
    if posix_spawn(&pid, exe, nil, &attrs, argv, environ) == 0 {
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        exit((status >> 8) & 0xff)
    }
}

func usage() -> Never {
    print("""
    usage: wave today                   events and tasks for today
           wave task add <title> [--list <name>] [--due "YYYY-MM-DD[ HH:mm]"]
           wave task list [<list>]      (default: today)
           wave task done <id>
    Add --json for machine-readable output.
    """)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
let json = args.contains("--json")
args.removeAll { $0 == "--json" }

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...i + 1)
    return v
}

func parseDate(_ s: String) -> Date? {
    let f = DateFormatter()
    for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
        f.dateFormat = format
        if let d = f.date(from: s) { return d }
    }
    return nil
}

let iso = ISO8601DateFormatter()

func taskRows(_ items: [EKReminder]) -> [[String: Any]] {
    items.map { ["id": $0.id, "title": $0.title ?? "", "list": $0.calendar.title, "due": $0.dueDate.map(iso.string) as Any] }
}

func eventRows(_ events: [EKEvent]) -> [[String: Any]] {
    events.map { ["title": $0.title ?? "", "calendar": $0.calendar.title, "allDay": $0.isAllDay,
                  "start": iso.string(from: $0.startDate), "end": iso.string(from: $0.endDate)] }
}

func printJSON(_ object: Any) {
    print(String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self))
}

func emit(_ items: [EKReminder]) {
    if json { printJSON(taskRows(items)); return }
    for r in items {
        let due = r.dueDate.map { "  " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
        print("\(r.id)  \(r.title ?? "")\(due)  [\(r.calendar.title)]")
    }
}

guard !args.isEmpty else { usage() }
let listName = option("--list")
let due = option("--due")
var command = args.removeFirst()
if command == "task" {
    guard !args.isEmpty else { usage() }
    command += " " + args.removeFirst()
}

let store = Store()

func run() async throws {
    await store.load()
    guard store.authorized else {
        print("Reminders access denied (status \(EKEventStore.authorizationStatus(for: .reminder).rawValue))\(store.accessError.map { ": " + $0 } ?? "").")
        print("Allow it in System Settings > Privacy & Security > Reminders, or run: tccutil reset Reminders")
        exit(1)
    }
    func list(named name: String?) -> EKCalendar? { name.flatMap { n in store.lists.first { $0.title.caseInsensitiveCompare(n) == .orderedSame } } }

    switch command {
    case "today":
        await store.fetchEvents()
        await store.fetch(.today)
        if json { printJSON(["events": eventRows(store.events), "tasks": taskRows(store.items)]); return }
        for e in store.events {
            let when = e.isAllDay ? "All day" : "\(e.startDate.formatted(date: .omitted, time: .shortened))–\(e.endDate.formatted(date: .omitted, time: .shortened))"
            print("\(when)  \(e.title ?? "")  [\(e.calendar.title)]")
        }
        if !store.events.isEmpty, !store.items.isEmpty { print("") }
        emit(store.items)
    case "task add":
        guard let title = args.first else { usage() }
        if let due, parseDate(due) == nil { print("Bad --due. Use YYYY-MM-DD or \"YYYY-MM-DD HH:mm\"."); exit(2) }
        try store.add(title, to: list(named: listName), due: due.flatMap(parseDate))
        await store.fetch(.list(list(named: listName) ?? store.ek.defaultCalendarForNewReminders()!))
        emit(store.items.filter { $0.title == title }.suffix(1).map { $0 })
    case "task list":
        if let name = args.first {
            guard let l = list(named: name) else { print("No list named \(name)."); exit(1) }
            await store.fetch(.list(l))
        } else {
            await store.fetch(.today)
        }
        emit(store.items)
    case "task done":
        guard let id = args.first, let r = store.reminder(id: id) else { print("No task with that id."); exit(1) }
        r.isCompleted = true
        try store.save(r)
        print("Done: \(r.title ?? "")")
    default:
        usage()
    }
}

// EventKit answers through the main queue; a plain top-level await never pumps it.
Task { try await run(); exit(0) }
RunLoop.main.run()
