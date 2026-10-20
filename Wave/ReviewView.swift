import SwiftUI
import SwiftData
import EventKit

/// The week in three cards: what got done, how the habits went, what the money did.
struct ReviewPage: View {
    let store: Store
    let finance: Finance
    @Query(sort: \Habit.created) private var habits: [Habit]
    @State private var offset = 0
    @State private var completed: [EKReminder] = []
    @State private var events: [EKEvent] = []

    private var cal: Calendar { Calendar.current }
    private var interval: DateInterval {
        let anchor = cal.date(byAdding: .weekOfYear, value: offset, to: .now)!
        return cal.dateInterval(of: .weekOfYear, for: anchor)!
    }

    var body: some View {
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: interval.start)! }
        let week = finance.transactions.filter { interval.contains($0.date) }
        let income = week.filter { $0.value > 0 }.reduce(Decimal(0)) { $0 + $1.value }
        let spent = -week.filter { $0.value < 0 }.reduce(Decimal(0)) { $0 + $1.value }
        let habitDays = habits.map { h in days.filter { h.isDone($0) && $0 <= .now }.count }
        let possible = habits.count * days.filter { $0 <= .now }.count
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Review").rise()
            Heading(muted: offset == 0 ? "This week so far." : "Week of \(interval.start.formatted(.dateTime.day().month(.wide))).",
                    strong: "\(completed.count) task\(completed.count == 1 ? "" : "s") done, \(events.count) event\(events.count == 1 ? "" : "s").")
                .padding(.top, 20).rise(0.05)
            HStack(spacing: 8) {
                Button { offset -= 1 } label: { Chip(text: "‹ Previous") }.buttonStyle(PressStyle())
                Button { offset = 0 } label: { Chip(text: "This week", selected: offset == 0) }.buttonStyle(PressStyle())
                Button { offset = min(0, offset + 1) } label: { Chip(text: "Next ›") }.buttonStyle(PressStyle()).opacity(offset < 0 ? 1 : 0.3)
            }
            .padding(.top, 36).rise(0.1)

            HStack(alignment: .top, spacing: 16) {
                card {
                    Icon("check-circle", size: 30, color: Theme.brand, weight: .fill)
                    Text("\(completed.count) done").font(.wave(24, .medium)).tracking(-0.6).padding(.top, 24)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(completed.prefix(7)) { r in
                            Text(r.title ?? "").font(.wave(16)).foregroundStyle(Theme.ink.opacity(0.7)).lineLimit(1)
                        }
                        if completed.isEmpty { Text("Nothing checked off yet.").foregroundStyle(Theme.ink.opacity(0.6)) }
                    }
                    .padding(.top, 16)
                }
                .rise(0.15)

                VStack(alignment: .leading, spacing: 0) {
                    Icon("flame", size: 32, color: Theme.paper.opacity(0.4), weight: .fill)
                    Text(possible == 0 ? "No habits" : "\(Int(Double(habitDays.reduce(0, +)) / Double(possible) * 100))% of habits")
                        .font(.wave(24, .medium)).tracking(-0.6).padding(.top, 24)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(habits.enumerated()), id: \.element.persistentModelID) { i, h in
                            HStack(spacing: 10) {
                                Text(h.name).font(.wave(16)).lineLimit(1)
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(days, id: \.self) { d in
                                        RoundedRectangle(cornerRadius: 2).fill(d > .now ? Theme.paper.opacity(0.08) : h.isDone(d) ? h.tint : Theme.paper.opacity(0.2)).frame(width: 10, height: 10)
                                    }
                                }
                                Text("\(habitDays[i])").font(.wave(14)).foregroundStyle(Theme.paper.opacity(0.6)).monospacedDigit().frame(width: 20, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 20)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.paper)
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
                .shadow(color: Theme.shadow.opacity(0.4), radius: 16, x: 16, y: 24)
                .rise(0.2)

                card {
                    Icon("credit-card", size: 30, color: Theme.ink.opacity(0.4), weight: .fill)
                    Text(income, format: .currency(code: "BRL")).font(.wave(24, .medium)).tracking(-0.6).foregroundStyle(Theme.brand).padding(.top, 24)
                    Text("in").foregroundStyle(Theme.ink.opacity(0.6))
                    Text(spent, format: .currency(code: "BRL")).font(.wave(24, .medium)).tracking(-0.6).padding(.top, 12)
                    Text("out").foregroundStyle(Theme.ink.opacity(0.6))
                    if let top = Dictionary(grouping: week.filter { $0.value < 0 }, by: { $0.category ?? "Uncategorized" })
                        .map({ ($0.key, -$0.value.reduce(Decimal(0)) { $0 + $1.value }) }).max(by: { $0.1 < $1.1 }) {
                        Text("Most on \(top.0): \(top.1.formatted(.currency(code: "BRL")))").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).padding(.top, 16)
                    }
                }
                .rise(0.25)
            }
            .padding(.top, 48)
        }
        .task(id: offset) {
            completed = await store.completed(from: interval.start, to: interval.end)
            events = await store.events(from: interval.start, to: interval.end)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content(); Spacer(minLength: 0) }
            .padding(32)
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
    }
}
