import SwiftUI
import SwiftData
import EventKit
import MapKit

/// The site's Home, as a dashboard: hero, the three social-proof cards, a featured grid (calendar), rows, FAQ rows.
struct HomePage: View {
    let store: Store
    let finance: Finance
    @Environment(\.modelContext) private var context
    @State private var notes: [Note] = []
    @Environment(UI.self) private var ui
    @Query(sort: \Habit.created) private var habits: [Habit]
    @State private var upcoming: [EKReminder] = []
    @State private var monthEvents: [EKEvent] = []
    @State private var month = Date.now
    @State private var selectedDay = Date.now
    @State private var weather = Weather()
    @State private var commute = Commute()
    @State private var todos: [Todo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            HStack(alignment: .top, spacing: 16) {
                TodayCard(events: todayEvents).rise(0.15)
                MoneyCard(finance: finance).rise(0.2)
                HabitsDeck(habits: habits).rise(0.25)
            }
            .padding(.top, 64)
            HStack(alignment: .top, spacing: 16) {
                WeatherCard(weather: weather).rise(0.3)
                CommuteCard(commute: commute).rise(0.35)
            }
            .padding(.top, 16)

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
            Heading(muted: "To do, and due in the next 7 days.", strong: todos.isEmpty && upcoming.isEmpty ? "All clear." : "\(todos.count) task\(todos.count == 1 ? "" : "s"), \(upcoming.count) reminder\(upcoming.count == 1 ? "" : "s").")
                .padding(.top, 20).rise(0.45)
            LazyVStack(spacing: 12) {
                ForEach(todos.prefix(5)) { t in TodoRow(todo: t, reload: { todos = Todo.open(context) }).rise(0.5) }
                ForEach(Array(upcoming.prefix(6).enumerated()), id: \.element.id) { i, r in
                    TaskRow(reminder: r, store: store, reload: { Task { await load() } }).rise(0.5 + Double(i) * 0.05)
                }
            }
            .padding(.top, 36)
            if upcoming.count > 6 {
                SecondaryButton(title: "See all \(upcoming.count)") { ui.page = .today }.padding(.top, 20)
            }

            if !notes.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent notes").font(.wave(36, .medium)).tracking(-0.9)
                    Spacer()
                    SecondaryButton(title: "See all") { ui.page = .notes }
                }
                .padding(.top, 96)
                VStack(spacing: 6) {
                    ForEach(notes) { note in NoteRow(note: note, selected: false) { ui.openNote(note) } }
                }
                .cardFrame()
                .padding(.top, 40)
            }
        }
        .task { await load() }
        .task(id: month) { await loadMonth() }
        .task { while !Task.isCancelled { await weather.refresh(); try? await Task.sleep(for: .seconds(1800)) } }
        .task { while !Task.isCancelled { await commute.refresh(); try? await Task.sleep(for: .seconds(600)) } }
        .task {
            notes = Note.fetch(context, limit: 4)
            finance.load()
            if finance.hasKey, finance.fetched.map({ Date.now.timeIntervalSince($0) > 3600 }) ?? true { await finance.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await load(); await loadMonth() } }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in todos = Todo.open(context) }
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

    private func load() async {
        upcoming = await store.upcoming(days: 7)
        todos = Todo.open(context)
    }

    private func loadMonth() async {
        let cal = Calendar.current
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let from = cal.date(byAdding: .day, value: -7, to: first)!
        let to = cal.date(byAdding: .day, value: 49, to: first)!
        monthEvents = await store.events(from: min(from, cal.startOfDay(for: .now)), to: max(to, cal.endOfToday))
    }
}

/// Now, high and low, and the next six hours. Open-Meteo, located by the Mac or by the city in Settings.
struct WeatherCard: View {
    let weather: Weather
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let f = weather.forecast {
                let now = WeatherCodes.describe(f.code, isDay: f.isDay)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(f.temperature.rounded()))°").font(.wave(40, .medium)).tracking(-1).monospacedDigit()
                        Text("\(now.label)\(weather.place.isEmpty ? "" : " · " + weather.place)").foregroundStyle(Theme.ink.opacity(0.6))
                        Text("H \(Int(f.high.rounded()))° · L \(Int(f.low.rounded()))°").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5))
                    }
                    Spacer()
                    Icon(now.icon, size: 44, weight: .fill)
                }
                HStack(spacing: 0) {
                    ForEach(f.hours) { h in
                        VStack(spacing: 6) {
                            Text(h.time.formatted(.dateTime.hour())).font(.wave(12)).foregroundStyle(Theme.ink.opacity(0.5))
                            Icon(WeatherCodes.describe(h.code, isDay: true).icon, size: 16, color: Theme.ink.opacity(0.7), weight: .fill)
                            Text("\(Int(h.temperature.rounded()))°").font(.wave(13, .medium)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 24)
            } else {
                Icon("cloud-sun", size: 34, color: Theme.ink.opacity(0.4), weight: .fill)
                Text("Weather").font(.wave(24, .medium)).tracking(-0.6).padding(.top, 24)
                Text(weather.error ?? "Finding where you are…").foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(4).padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
    }
}

/// Driving time with traffic between home and work, direction by the hour, tap the arrow to flip. The route
/// is drawn on an Apple map that fills the right half of the card.
struct CommuteCard: View {
    let commute: Commute
    var body: some View {
        HStack(spacing: 16) {
            details
            if let route = commute.route, let from = commute.from, let to = commute.to {
                Map(initialPosition: .rect(route.polyline.boundingMapRect.insetBy(dx: -route.polyline.boundingMapRect.width * 0.2, dy: -route.polyline.boundingMapRect.height * 0.2)), interactionModes: []) {
                    MapPolyline(route.polyline).stroke(Theme.violet, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    Annotation("", coordinate: from) { Circle().fill(Theme.ink).frame(width: 10, height: 10).overlay(Circle().stroke(Theme.paper, lineWidth: 2)) }
                    Annotation("", coordinate: to) { Circle().fill(Theme.violet).frame(width: 10, height: 10).overlay(Circle().stroke(Theme.paper, lineWidth: 2)) }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: true))
                .mapControlVisibility(.hidden)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusBlock))
                .id(route.polyline.pointCount)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !commute.hasAddresses {
                Icon("car", size: 34, color: Theme.ink.opacity(0.4), weight: .fill)
                Text("Commute").font(.wave(24, .medium)).tracking(-0.6).padding(.top, 24)
                Text("Add your home and work addresses in Settings (⌘,).").foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(4).padding(.top, 12)
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let m = commute.minutes {
                            Text("\(m) min").font(.wave(40, .medium)).tracking(-1).monospacedDigit()
                        } else {
                            Text(commute.error == nil ? "…" : "—").font(.wave(40, .medium)).tracking(-1)
                        }
                        Button(action: commute.flip) {
                            HStack(spacing: 8) {
                                Text(commute.toWork ? "Home" : "Work").font(.wave(16, .medium))
                                Icon("arrow-right", size: 14)
                                Text(commute.toWork ? "Work" : "Home").font(.wave(16, .medium))
                                Icon("arrows-left-right", size: 12, color: Theme.ink.opacity(0.4))
                            }
                        }
                        .buttonStyle(PressStyle())
                        if let km = commute.kilometers {
                            Text("\(km.formatted(.number.precision(.fractionLength(0)))) km\(commute.via.map { " · via \($0)" } ?? "") · by car")
                                .font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5))
                        }
                        if let error = commute.error { Text(error).font(.wave(13)).foregroundStyle(Theme.danger) }
                    }
                    Spacer()
                    if commute.route == nil { Icon("car", size: 44, weight: .fill) }
                }
                Spacer(minLength: 16)
                if let fetched = commute.fetched {
                    Text("Apple Maps · updated \(fetched, format: .relative(presentation: .named))").font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Light social-proof card: `rounded-4xl bg-ink/[0.04] p-8`.
struct TodayCard: View {
    let events: [EKEvent]
    @State private var gmail = Gmail.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Icon("calendar-blank", size: 30, weight: .fill)
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
            if gmail.connected {
                Text(gmail.messages.isEmpty ? "Inbox zero." : "\(gmail.messages.count) unread email\(gmail.messages.count == 1 ? "" : "s").")
                    .font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 16)
            }
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
        .task { if gmail.connected, gmail.messages.isEmpty { await gmail.load() } }
    }
}

/// The dark quote card: `rounded-4xl bg-ink p-8 text-paper shadow-[16px_24px_32px]`.
struct MoneyCard: View {
    let finance: Finance
    var body: some View {
        let checking = finance.accounts.first { $0.type == "BANK" }
        let credit = finance.accounts.first { $0.type == "CREDIT" }
        VStack(alignment: .leading, spacing: 0) {
            Icon("credit-card", size: 36, color: Theme.paper.opacity(0.4), weight: .fill)
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
        .shadow(color: Theme.shadow.opacity(0.4), radius: 16, x: 16, y: 24)
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
                        Icon(isDone ? "check-circle" : habit.icon, size: 28, color: isDone ? Theme.brand : habit.tint, weight: .fill)
                    }
                    .padding(.horizontal, 24)
                    .frame(height: 64)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                    .shadow(color: Theme.shadow.opacity(0.06), radius: 10, y: 10)
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
                        Icon(habit.icon, size: 16, color: Theme.brand, weight: .fill)
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
                monthButton("caret-left", -1)
                monthButton("caret-right", 1)
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
            Icon(icon, size: 15, color: Theme.ink)
                .frame(width: 36, height: 36).background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressStyle())
    }
}

/// FAQ container with the selected day's events.
struct DayEvents: View {
    let day: Date
    let events: [EKEvent]
    @Environment(UI.self) private var ui
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
                .contentShape(Rectangle())
                .onTapGesture { ui.open(.editEvent(e)) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .cardFrame()
    }
}
