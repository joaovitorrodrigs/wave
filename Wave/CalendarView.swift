import SwiftUI
import EventKit

struct CalendarPage: View {
    let store: Store
    @Environment(UI.self) private var ui
    @State private var week = true
    @State private var anchor = Date.now
    @State private var month = Date.now
    @State private var selectedDay = Date.now
    @State private var events: [EKEvent] = []

    private var cal: Calendar { Calendar.current }
    private var weekStart: Date { cal.dateInterval(of: .weekOfYear, for: anchor)!.start }
    private var weekDays: [Date] { (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekStart)! } }
    private var rangeKey: String { week ? "w\(weekStart.timeIntervalSince1970)" : "m\(month.formatted(.dateTime.year().month()))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Calendar").rise()
            Heading(muted: week ? "Week of \(weekStart.formatted(.dateTime.day().month(.wide)))." : month.formatted(.dateTime.month(.wide).year()) + ".",
                    strong: "\(events.count) event\(events.count == 1 ? "" : "s").")
                .padding(.top, 20).rise(0.05)

            HStack(spacing: 8) {
                Button { week = true } label: { Chip(text: "Week", selected: week) }.buttonStyle(PressStyle())
                Button { week = false } label: { Chip(text: "Month", selected: !week) }.buttonStyle(PressStyle())
                Spacer()
                Button { shift(-1) } label: { Chip(text: "‹") }.buttonStyle(PressStyle())
                Button { anchor = .now; month = .now; selectedDay = .now } label: { Chip(text: "Today") }.buttonStyle(PressStyle())
                Button { shift(1) } label: { Chip(text: "›") }.buttonStyle(PressStyle())
            }
            .padding(.top, 36).rise(0.1)

            if week {
                WeekView(days: weekDays, events: events).padding(.top, 40).rise(0.15)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    MonthGrid(month: $month, selected: $selectedDay, eventDays: Set(events.map { cal.startOfDay(for: $0.startDate) }))
                        .padding(32)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
                    DayEvents(day: selectedDay, events: events.filter { cal.isDate($0.startDate, inSameDayAs: selectedDay) })
                }
                .padding(.top, 40).rise(0.15)
            }
        }
        .task(id: rangeKey) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await load() } }
    }

    private func shift(_ delta: Int) {
        if week { anchor = cal.date(byAdding: .weekOfYear, value: delta, to: anchor)! }
        else { month = cal.date(byAdding: .month, value: delta, to: month)! }
    }

    private func load() async {
        if week {
            events = await store.events(from: weekStart, to: cal.date(byAdding: .day, value: 7, to: weekStart)!)
        } else {
            let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
            events = await store.events(from: cal.date(byAdding: .day, value: -7, to: first)!, to: cal.date(byAdding: .day, value: 49, to: first)!)
        }
    }
}

/// Seven paper columns in one frame; each event a block, each day a "+" to add one.
struct WeekView: View {
    let days: [Date]
    let events: [EKEvent]
    @Environment(UI.self) private var ui

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(days, id: \.self) { day in
                let today = Calendar.current.isDateInToday(day)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.5))
                        Text(day.formatted(.dateTime.day())).font(.wave(18, .medium))
                            .foregroundStyle(today ? Theme.paper : Theme.ink)
                            .frame(width: 32, height: 32)
                            .background(today ? Theme.violet : .clear, in: Circle())
                    }
                    .padding(.bottom, 6)
                    ForEach(events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }, id: \.self) { e in
                        Button { ui.open(.editEvent(e)) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(cgColor: e.calendar.cgColor)).frame(width: 6, height: 6)
                                    Text(e.isAllDay ? "All day" : e.startDate.formatted(date: .omitted, time: .shortened))
                                        .font(.wave(12)).foregroundStyle(Theme.ink.opacity(0.5)).monospacedDigit()
                                }
                                Text(e.title ?? "").font(.wave(14, .medium)).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PressStyle())
                    }
                    Button { ui.open(.newEvent(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)) } label: {
                        Icon("plus", size: 14, color: Theme.ink.opacity(0.35))
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                    .buttonStyle(PressStyle())
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 440, alignment: .top)
                .cardBlock()
            }
        }
        .cardFrame()
    }
}

struct EventEditor: View {
    let store: Store
    let event: EKEvent?
    let day: Date
    @Environment(UI.self) private var ui
    @State private var title = ""
    @State private var notes = ""
    @State private var allDay = false
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var calendar: EKCalendar?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PanelTitle(text: event == nil ? "New event" : "Edit event")
                    Spacer()
                    if let event { SecondaryButton(title: "Delete", danger: true) { try? store.delete(event); ui.close() } }
                }
                VStack(spacing: 8) {
                    TextField("Title", text: $title).waveField()
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5).waveField()
                }
                VStack(spacing: 8) {
                    Switch(title: "All day", isOn: $allDay)
                    DateField(title: "Starts", date: $start)
                    if !allDay { DateField(title: "Ends", date: $end) }
                    if !store.eventCalendars.isEmpty {
                        Select(title: "Calendar", value: $calendar, options: store.eventCalendars.map { ($0, $0.title) })
                    }
                }
                PanelButtons(primary: event == nil ? "Add event" : "Save", disabled: title.isEmpty, action: save)
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 760)
        .panel(width: 480)
        .onAppear(perform: load)
        .onChange(of: start) { if end <= start { end = start.addingTimeInterval(3600) } }
    }

    private func load() {
        if let event {
            title = event.title ?? ""
            notes = event.notes ?? ""
            allDay = event.isAllDay
            start = event.startDate
            end = event.endDate
            calendar = event.calendar
        } else {
            start = day
            end = day.addingTimeInterval(3600)
            calendar = store.ek.defaultCalendarForNewEvents ?? store.eventCalendars.first
        }
    }

    private func save() {
        let e = event ?? EKEvent(eventStore: store.ek)
        e.title = title
        e.notes = notes.isEmpty ? nil : notes
        e.isAllDay = allDay
        e.startDate = allDay ? Calendar.current.startOfDay(for: start) : start
        e.endDate = allDay ? Calendar.current.startOfDay(for: start) : max(end, start.addingTimeInterval(900))
        if let calendar { e.calendar = calendar }
        try? store.save(e)
        ui.close()
    }
}
