import SwiftUI
import SwiftData
import EventKit

/// The site's Home, as a dashboard: hero, the three social-proof cards, a featured grid (calendar), rows, FAQ rows.
struct HomePage: View {
    let store: Store
    let notes: Notes
    let finance: Finance
    @Environment(UI.self) private var ui
    @Query(sort: \Habit.created) private var habits: [Habit]
    @State private var upcoming: [EKReminder] = []
    @State private var monthEvents: [EKEvent] = []
    @State private var month = Date.now
    @State private var selectedDay = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            HStack(alignment: .top, spacing: 16) {
                TodayCard(events: todayEvents).rise(0.15)
                MoneyCard(finance: finance).rise(0.2)
                HabitsDeck(habits: habits).rise(0.25)
            }
            .padding(.top, 64)

            HStack(alignment: .firstTextBaseline) {
                Text("Calendar").font(.wave(36, .medium)).tracking(-0.9)
                Spacer()
                SecondaryButton(title: "Open today") { ui.page = .today }
            }
            .padding(.top, 96).rise(0.3)
            HStack(alignment: .top, spacing: 16) {
                MonthGrid(month: $month, selected: $selectedDay, eventDays: eventDays)
                    .padding(32)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
                DayEvents(day: selectedDay, events: selectedEvents)
            }
            .padding(.top, 40).rise(0.35)

            Eyebrow(text: "Tasks").padding(.top, 96).rise(0.4)
            Heading(muted: "Due in the next 7 days.", strong: upcoming.isEmpty ? "All clear." : "\(upcoming.count) open.")
                .padding(.top, 20).rise(0.45)
            LazyVStack(spacing: 12) {
                ForEach(Array(upcoming.prefix(6).enumerated()), id: \.element.id) { i, r in
                    TaskRow(reminder: r, store: store, reload: { Task { await load() } }).rise(0.5 + Double(i) * 0.05)
                }
            }
            .padding(.top, 36)
            if upcoming.count > 6 {
                SecondaryButton(title: "See all \(upcoming.count)") { ui.page = .today }.padding(.top, 20)
            }

            if !notes.items.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent notes").font(.wave(36, .medium)).tracking(-0.9)
                    Spacer()
                    SecondaryButton(title: "See all") { ui.page = .notes }
                }
                .padding(.top, 96)
                VStack(spacing: 6) {
                    ForEach(notes.items.prefix(4)) { note in NoteRow(note: note) { notes.open(note) } }
                }
                .cardFrame()
                .padding(.top, 40)
            }
        }
        .task { await load() }
        .task(id: month) { await loadMonth() }
        .task {
            finance.load()
            if finance.hasKey, finance.fetched.map({ Date.now.timeIntervalSince($0) > 3600 }) ?? true { await finance.refresh() }
            if notes.items.isEmpty { await notes.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await load(); await loadMonth() } }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 48) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) { LiveDot(); Eyebrow(text: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())) }
                (Text(greeting + ", ").foregroundStyle(Theme.ink.opacity(0.4)) + Text(firstName + ".").foregroundStyle(Theme.ink))
                    .font(.wave(40, .medium)).tracking(-1).lineSpacing(2)
            }
            .rise()
            Spacer(minLength: 0)
            Text(summary)
                .foregroundStyle(Theme.ink.opacity(0.7)).lineSpacing(5)
                .frame(maxWidth: 380, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .rise(0.1)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<12: "Good morning"
        case ..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var firstName: String { NSFullUserName().split(separator: " ").first.map(String.init) ?? "there" }

    private var summary: String {
        let due = upcoming.filter { ($0.dueDate ?? .distantFuture) < Calendar.current.endOfToday }.count
        let done = habits.filter { $0.isDone(.now) }.count
        var parts = ["\(due) task\(due == 1 ? "" : "s") due today", "\(todayEvents.count) event\(todayEvents.count == 1 ? "" : "s")"]
        if !habits.isEmpty { parts.append("\(done) of \(habits.count) habits done") }
        return parts.joined(separator: ", ") + ". " + (due == 0 && todayEvents.isEmpty ? "A quiet day. Use it well." : "Start with what is due.")
    }

    private var todayEvents: [EKEvent] { monthEvents.filter { Calendar.current.isDateInToday($0.startDate) } }
    private var selectedEvents: [EKEvent] { monthEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDay) } }
    private var eventDays: Set<Date> { Set(monthEvents.map { Calendar.current.startOfDay(for: $0.startDate) }) }

    private func load() async { upcoming = await store.upcoming(days: 7) }

    private func loadMonth() async {
        let cal = Calendar.current
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let from = cal.date(byAdding: .day, value: -7, to: first)!
        let to = cal.date(byAdding: .day, value: 49, to: first)!
        monthEvents = await store.events(from: min(from, cal.startOfDay(for: .now)), to: max(to, cal.endOfToday))
    }
}

/// Light social-proof card: `rounded-4xl bg-ink/[0.04] p-8`.
struct TodayCard: View {
    let events: [EKEvent]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "calendar").font(.system(size: 28, weight: .regular))
            Text("Today").font(.wave(24, .medium)).tracking(-0.6).padding(.top, 24)
            if events.isEmpty {
                Text("No events. The day is yours.").foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(4).padding(.top, 12)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(events.prefix(4), id: \.self) { e in
                        HStack(spacing: 12) {
                            Text(e.isAllDay ? "All day" : e.startDate.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(Theme.ink.opacity(0.5)).monospacedDigit().frame(width: 60, alignment: .leading)
                            Text(e.title ?? "").font(.wave(16, .medium)).lineLimit(1)
                        }
                    }
                }
                .padding(.top, 16)
            }
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
    }
}

/// The dark quote card: `rounded-4xl bg-ink p-8 text-paper shadow-[16px_24px_32px]`.
struct MoneyCard: View {
    let finance: Finance
    var body: some View {
        let checking = finance.accounts.first { $0.type == "BANK" }
        let credit = finance.accounts.first { $0.type == "CREDIT" }
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "creditcard.fill").font(.system(size: 34)).foregroundStyle(Theme.paper.opacity(0.4))
            if let checking {
                Text(checking.value, format: .currency(code: checking.currencyCode))
                    .font(.wave(30, .medium)).tracking(-0.8).monospacedDigit().padding(.top, 24)
                Text("in \(checking.title.capitalized)").foregroundStyle(Theme.paper.opacity(0.6)).padding(.top, 4)
            } else {
                Text(finance.hasKey ? "Loading your accounts…" : "Connect your bank in Settings (⌘,).")
                    .font(.wave(20, .medium)).tracking(-0.5).lineSpacing(3).padding(.top, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 24)
            if let credit {
                Text(credit.value, format: .currency(code: credit.currencyCode)).font(.wave(16, .medium))
                Text("credit card bill\(credit.creditData?.balanceDueDate.map { " · due \($0)" } ?? "")")
                    .foregroundStyle(Theme.paper.opacity(0.6))
            }
        }
        .foregroundStyle(Theme.paper)
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
        .shadow(color: Theme.ink.opacity(0.4), radius: 16, x: 16, y: 24)
    }
}

/// The trusted card: brand pill on the top edge, then the stats deck of paper rows.
struct HabitsDeck: View {
    let habits: [Habit]
    var body: some View {
        let done = habits.filter { $0.isDone(.now) }
        VStack(spacing: 16) {
            if habits.isEmpty {
                Text("No habits yet. Add one in Habits.").foregroundStyle(Theme.ink.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(habits.prefix(4)) { habit in
                let isDone = habit.isDone(.now)
                Button { habit.toggle(.now) } label: {
                    HStack {
                        Text(habit.name).font(.wave(16, .medium)).lineLimit(1)
                        Spacer()
                        Image(systemName: isDone ? "checkmark.circle.fill" : habit.icon)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(isDone ? Theme.brand : habit.tint)
                    }
                    .padding(.horizontal, 24)
                    .frame(height: 64)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                    .shadow(color: Theme.ink.opacity(0.06), radius: 10, y: 10)
                }
                .buttonStyle(PressStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(32).padding(.top, 8)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
        .overlay(alignment: .top) {
            HStack(spacing: 0) {
                HStack(spacing: -10) {
                    ForEach(done.prefix(4)) { habit in
                        Image(systemName: habit.icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.brand)
                            .frame(width: 36, height: 36).background(Theme.paper, in: Circle())
                            .overlay(Circle().stroke(Theme.brand, lineWidth: 2))
                    }
                }
                Text(habits.isEmpty ? "Nothing tracked" : "\(done.count) of \(habits.count) done today")
                    .font(.wave(16, .medium)).foregroundStyle(Theme.paper)
                    .padding(.leading, done.isEmpty ? 10 : 12).padding(.trailing, 16)
            }
            .padding(6)
            .background(Theme.brand, in: Capsule())
            .offset(y: -24)
        }
    }
}

struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selected: Date
    let eventDays: Set<Date>

    var body: some View {
        let cal = Calendar.current
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let offset = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -offset, to: first)!
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let weekdays = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        VStack(spacing: 16) {
            HStack {
                Text(month, format: .dateTime.month(.wide).year()).font(.wave(20, .medium)).tracking(-0.5)
                Spacer()
                monthButton("chevron.left", -1)
                monthButton("chevron.right", 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(weekdays, id: \.self) { Text($0).font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.4)) }
                ForEach(0..<42, id: \.self) { i in
                    let day = cal.date(byAdding: .day, value: i, to: gridStart)!
                    let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
                    let isToday = cal.isDateInToday(day)
                    let isSelected = cal.isDate(day, inSameDayAs: selected)
                    Button { selected = day } label: {
                        VStack(spacing: 4) {
                            Text(day, format: .dateTime.day()).font(.wave(15, isToday ? .semibold : .regular))
                            Circle().fill(eventDays.contains(cal.startOfDay(for: day)) ? (isSelected ? Theme.paper : Theme.brand) : .clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .foregroundStyle(isSelected ? Theme.paper : Theme.ink.opacity(inMonth ? 1 : 0.3))
                        .background(isSelected ? Theme.ink : isToday ? Theme.violet.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    private func monthButton(_ icon: String, _ delta: Int) -> some View {
        Button { month = Calendar.current.date(byAdding: .month, value: delta, to: month)! } label: {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36).background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressStyle())
    }
}

/// FAQ container with the selected day's events.
struct DayEvents: View {
    let day: Date
    let events: [EKEvent]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.wave(20, .medium)).tracking(-0.5).padding(.horizontal, 20).padding(.vertical, 14)
            if events.isEmpty {
                Text("Nothing scheduled.").foregroundStyle(Theme.ink.opacity(0.6))
                    .padding(.horizontal, 20).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading).cardBlock()
            }
            ForEach(events, id: \.self) { e in
                HStack(spacing: 16) {
                    Text(e.isAllDay ? "All day" : "\(e.startDate.formatted(date: .omitted, time: .shortened))–\(e.endDate.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(Theme.ink.opacity(0.5)).monospacedDigit().frame(width: 120, alignment: .leading)
                    Text(e.title ?? "").font(.wave(18, .medium)).tracking(-0.4).lineLimit(1)
                    Spacer()
                    Circle().fill(Color(cgColor: e.calendar.cgColor)).frame(width: 8, height: 8)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .cardBlock()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .cardFrame()
    }
}
