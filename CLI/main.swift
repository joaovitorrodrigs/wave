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
    usage: wave task add <title> [--list <name>] [--due "YYYY-MM-DD[ HH:mm]"]
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

func emit(_ items: [EKReminder]) {
    if json {
        let rows = items.map { ["id": $0.id, "title": $0.title ?? "", "list": $0.calendar.title,
                                "due": $0.dueDate.map { ISO8601DateFormatter().string(from: $0) } as Any] }
        print(String(decoding: try! JSONSerialization.data(withJSONObject: rows), as: UTF8.self))
    } else {
        for r in items {
            let due = r.dueDate.map { "  " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
            print("\(r.id)  \(r.title ?? "")\(due)  [\(r.calendar.title)]")
        }
    }
}

guard args.count >= 2, args.removeFirst() == "task" else { usage() }
let listName = option("--list")
let due = option("--due")
let command = args.removeFirst()

let reminders = Reminders()

func run() async throws {
    await reminders.load()
    guard reminders.authorized else {
        print("Reminders access denied (status \(EKEventStore.authorizationStatus(for: .reminder).rawValue))\(reminders.accessError.map { ": " + $0 } ?? "").")
        print("Allow it in System Settings > Privacy & Security > Reminders, or run: tccutil reset Reminders")
        exit(1)
    }
    func list(named name: String?) -> EKCalendar? { name.flatMap { n in reminders.lists.first { $0.title.caseInsensitiveCompare(n) == .orderedSame } } }

    switch command {
    case "add":
        guard let title = args.first else { usage() }
        if let due, parseDate(due) == nil { print("Bad --due. Use YYYY-MM-DD or \"YYYY-MM-DD HH:mm\"."); exit(2) }
        try reminders.add(title, to: list(named: listName), due: due.flatMap(parseDate))
        await reminders.fetch(.list(list(named: listName) ?? reminders.store.defaultCalendarForNewReminders()!))
        emit(reminders.items.filter { $0.title == title }.suffix(1).map { $0 })
    case "list":
        if let name = args.first {
            guard let l = list(named: name) else { print("No list named \(name)."); exit(1) }
            await reminders.fetch(.list(l))
        } else {
            await reminders.fetch(.today)
        }
        emit(reminders.items)
    case "done":
        guard let id = args.first, let r = reminders.reminder(id: id) else { print("No task with that id."); exit(1) }
        r.isCompleted = true
        try reminders.save(r)
        print("Done: \(r.title ?? "")")
    default:
        usage()
    }
}

// EventKit answers through the main queue; a plain top-level await never pumps it.
Task { try await run(); exit(0) }
RunLoop.main.run()
