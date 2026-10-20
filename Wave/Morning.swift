import Foundation
import AppKit
import SwiftData
import EventKit
import UserNotifications

/// One local notification at 8:00 with the day's events, tasks and habits. Rescheduled whenever the app becomes active.
enum Morning {
    static func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { await schedule() }
        }
        Task { await schedule() }
    }

    static func schedule() async {
        let store = Store()
        await store.load()
        guard store.authorized else { return }
        let cal = Calendar.current
        var fire = cal.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
        if fire <= .now { fire = cal.date(byAdding: .day, value: 1, to: fire)! }
        let dayStart = cal.startOfDay(for: fire)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let events = await store.events(from: dayStart, to: dayEnd)
        let tasks = await store.reminders(matching: store.ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: dayEnd, calendars: nil))
        let habits = (try? ModelContext(Habit.container).fetchCount(FetchDescriptor<Habit>())) ?? 0

        let content = UNMutableNotificationContent()
        content.title = "Good morning. " + fire.formatted(.dateTime.weekday(.wide).month(.wide).day()) + "."
        var parts = ["\(events.count) event\(events.count == 1 ? "" : "s")", "\(tasks.count) task\(tasks.count == 1 ? "" : "s") due"]
        if habits > 0 { parts.append("\(habits) habit\(habits == 1 ? "" : "s") to do") }
        content.body = parts.joined(separator: ", ") + "."
        if let first = events.first(where: { !$0.isAllDay }) {
            content.body += " First up: \(first.title ?? "") at \(first.startDate.formatted(date: .omitted, time: .shortened))."
        }
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["morning"])
        try? await center.add(UNNotificationRequest(identifier: "morning", content: content, trigger: trigger))
    }
}
