import SwiftData
import SwiftUI

@Model final class Habit {
    var name: String
    var icon: String
    var color: String
    // ponytail: days are local start-of-day instants; a timezone change can shift a day. Store "yyyy-MM-dd" strings if that bites.
    var days: [Date] = []
    var created = Date.now

    init(name: String, icon: String, color: String) {
        self.name = name
        self.icon = icon
        self.color = color
    }

    static let icons = ["person-simple-run", "barbell", "book", "pencil", "brain", "drop", "leaf", "fork-knife",
                        "bed", "sun", "moon", "music-note", "heart", "star", "currency-dollar", "laptop"]
    static let palette: [(String, Color)] = [("red", .red), ("orange", .orange), ("yellow", .yellow), ("green", .green),
                                             ("mint", .mint), ("teal", .teal), ("blue", .blue), ("indigo", .indigo),
                                             ("purple", .purple), ("pink", .pink)]
    var tint: Color { Self.palette.first { $0.0 == color }?.1 ?? .blue }

    func isDone(_ date: Date) -> Bool { days.contains(Calendar.current.startOfDay(for: date)) }

    func toggle(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if let i = days.firstIndex(of: day) { days.remove(at: i) } else { days.append(day) }
    }

    /// Consecutive days done, counted back from today, or from yesterday when today is still open.
    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if !isDone(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while isDone(day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }

    #if DEBUG
    static func selfCheck() {
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        let ago = { cal.date(byAdding: .day, value: -$0, to: today)! }
        let h = Habit(name: "t", icon: "star", color: "red")
        assert(h.streak == 0)
        h.toggle(ago(1)); h.toggle(ago(2))
        assert(h.streak == 2, "yesterday and the day before count while today is open")
        h.toggle(today)
        assert(h.streak == 3)
        h.toggle(ago(1))
        assert(h.streak == 1, "a gap ends the streak")
        assert(!h.isDone(ago(1)) && h.isDone(ago(2)))
    }
    #endif
}
