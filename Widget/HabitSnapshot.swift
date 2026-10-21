import Foundation

/// What the widget sees. The app writes `habits.json` into the widget's sandbox container; the widget writes
/// `toggles.json` back and the app folds those into the store. No entitlements, no shared signing needed.
struct HabitSnapshot: Codable, Identifiable {
    let id: Double          // created, as a stable handle
    var name: String
    var icon: String
    var color: String
    var days: [Date]        // start-of-day instants

    static let widgetBundle = "pro.wavestudio.wave.widget"

    /// Where the widget's sandbox keeps its Application Support, seen from outside the sandbox.
    static var bridgeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/\(widgetBundle)/Data/Library/Application Support/Wave")
    }

    func isDone(_ date: Date) -> Bool { days.contains(Calendar.current.startOfDay(for: date)) }

    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if !isDone(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while isDone(day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }
}

struct HabitToggle: Codable {
    let id: Double
    let day: Date
}
