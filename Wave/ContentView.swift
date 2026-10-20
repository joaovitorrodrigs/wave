import SwiftUI
import EventKit

enum Page: String, CaseIterable {
    case home = "Home", today = "Today", calendar = "Calendar", habits = "Habits", notes = "Notes"
    case finances = "Finances", clients = "Clients", review = "Review"
}

struct ContentView: View {
    @State private var ui = UI.shared
    @State private var store = Store()
    @State private var notes = Notes()
    @State private var finance = Finance()
    @State private var list: EKCalendar?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                NavBar(button: buttonTitle, icon: ui.page == .finances ? "arrows-clockwise" : "plus", action: primaryAction)
                ScrollView {
                    Group {
                        switch ui.page {
                        case .home: HomePage(store: store, notes: notes, finance: finance)
                        case .today: TodayPage(store: store, list: $list)
                        case .calendar: CalendarPage(store: store)
                        case .habits: HabitsPage()
                        case .notes: NotesPage(notes: notes)
                        case .finances: FinancePage(finance: finance)
                        case .clients: ClientsPage(store: store, finance: finance)
                        case .review: ReviewPage(store: store, finance: finance)
                        }
                    }
                    .id(ui.page)
                    .frame(maxWidth: 1200)
                    .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 96)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
            }
            ModalHost(store: store, notes: notes, finance: finance)
        }
        .environment(ui)
        .background(Theme.paper)
        .font(.wave(16))
        .foregroundStyle(Theme.ink)
        .tint(Theme.violet)
        .preferredColorScheme(.light)
        .frame(minWidth: 900, minHeight: 600)
        .task { await store.load(); await refresh() }
        .onChange(of: list) { Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await refresh() } }
    }

    private var buttonTitle: String {
        switch ui.page {
        case .home, .today, .review: "New task"
        case .calendar: "New event"
        case .habits: "New habit"
        case .notes: "New note"
        case .finances: "Refresh"
        case .clients: "New client"
        }
    }

    private func primaryAction() {
        if ui.page == .finances { Task { await finance.refresh() } } else { ui.open(ui.newItem) }
    }

    private func refresh() async {
        let selection: Selection = list.map { .list($0) } ?? .today
        await store.fetch(selection)
        if list == nil { await store.fetchEvents() }
    }
}

/// The site's navbar: brand left, links centered, settings and the ink button right. Sits under the hidden title bar.
struct NavBar: View {
    let button: String
    let icon: String
    let action: () -> Void
    @Environment(UI.self) private var ui

    var body: some View {
        ZStack {
            HStack(spacing: 24) {
                ForEach(Page.allCases, id: \.self) { p in
                    NavLink(title: p.rawValue, active: ui.page == p) { ui.page = p }
                }
            }
            HStack(spacing: 12) {
                Text("Wave").font(.wave(20, .semibold)).tracking(-0.5)
                Spacer()
                Button { ui.open(.palette) } label: { navIcon("magnifying-glass") }.buttonStyle(PressStyle())
                Button { ui.open(.settings) } label: { navIcon("gear-six") }.buttonStyle(PressStyle())
                PrimaryButton(title: button, icon: icon, action: action)
            }
        }
        .padding(.leading, 96).padding(.trailing, 40)
        .frame(height: 72)
    }

    private func navIcon(_ name: String) -> some View {
        Icon(name, size: 16, color: Theme.ink)
            .frame(width: 40, height: 40).background(Theme.chip, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
    }
}

struct NavLink: View {
    let title: String
    let active: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.wave(16)).foregroundStyle(Theme.ink.opacity(active || hover ? 1 : 0.7))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.2), value: hover)
    }
}

struct TodayPage: View {
    let store: Store
    @Binding var list: EKCalendar?
    @Environment(UI.self) private var ui
    @State private var newTitle = ""
    @State private var gmail = Gmail.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { LiveDot(); Eyebrow(text: "Today") }.rise()
            Heading(muted: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()) + ".", strong: summary)
                .padding(.top, 20).rise(0.05)

            HStack(spacing: 8) {
                chip("Today", nil)
                ForEach(store.lists, id: \.calendarIdentifier) { chip($0.title, $0) }
            }
            .padding(.top, 36).rise(0.1)

            if !store.authorized {
                Text("Allow Wave in System Settings > Privacy & Security > Reminders.")
                    .foregroundStyle(Theme.ink.opacity(0.6)).padding(.top, 48)
            }

            if list == nil, !store.events.isEmpty {
                Eyebrow(text: "Events").padding(.top, 56).rise(0.15)
                VStack(spacing: 6) {
                    ForEach(store.events, id: \.self) { e in
                        HStack(spacing: 20) {
                            Text(e.isAllDay ? "All day" : e.startDate.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(Theme.ink.opacity(0.5)).monospacedDigit().frame(width: 72, alignment: .leading)
                            Text(e.title ?? "").font(.wave(20, .medium)).tracking(-0.5)
                            Spacer()
                            Circle().fill(Color(cgColor: e.calendar.cgColor)).frame(width: 8, height: 8)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .cardBlock()
                    }
                }
                .cardFrame()
                .padding(.top, 20).rise(0.2)
            }

            if list == nil, gmail.connected {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(text: "Inbox")
                    Spacer()
                    if gmail.loading { Spinner() } else {
                        Button { Task { await gmail.load() } } label: { Chip(text: "Refresh") }.buttonStyle(PressStyle())
                    }
                }
                .padding(.top, 56).rise(0.15)
                if let error = gmail.error {
                    Text(error).font(.wave(14)).foregroundStyle(Theme.danger).padding(.top, 12)
                }
                if gmail.messages.isEmpty, !gmail.loading, gmail.error == nil {
                    Text("Inbox zero. Nothing unread.").foregroundStyle(Theme.ink.opacity(0.6)).padding(.top, 16)
                } else {
                    VStack(spacing: 6) {
                        ForEach(gmail.messages) { m in MailRow(message: m, store: store) }
                    }
                    .cardFrame()
                    .padding(.top, 20).rise(0.2)
                }
            }

            Eyebrow(text: list == nil ? "Tasks" : list!.title).padding(.top, 56).rise(0.2)
            LazyVStack(spacing: 12) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { i, r in
                    TaskRow(reminder: r, store: store, reload: reload).rise(0.25 + Double(min(i, 8)) * 0.05)
                }
                HStack(spacing: 16) {
                    Icon("plus", size: 16, color: Theme.ink.opacity(0.4))
                    TextField("New task, press Return", text: $newTitle).textFieldStyle(.plain).font(.wave(20, .medium)).onSubmit(add)
                }
                .padding(.horizontal, 32).padding(.vertical, 16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                .rise(0.3)
            }
            .padding(.top, 20)
        }
        .task { if gmail.connected, gmail.messages.isEmpty { await gmail.load() } }
    }

    private var summary: String {
        let tasks = "\(store.items.count) task\(store.items.count == 1 ? "" : "s")"
        if let list { return "\(tasks) open in \(list.title)." }
        let events = store.events.count
        return events == 0 ? "\(tasks) due." : "\(tasks) and \(events) event\(events == 1 ? "" : "s")."
    }

    private func chip(_ title: String, _ calendar: EKCalendar?) -> some View {
        Button { list = calendar } label: { Chip(text: title, selected: list == calendar) }.buttonStyle(PressStyle())
    }

    private func reload() { Task { await store.fetch(list.map { .list($0) } ?? .today) } }

    private func add() {
        guard !newTitle.isEmpty else { return }
        try? store.add(newTitle, to: list)
        newTitle = ""
        reload()
    }
}

/// FAQ-style row for an unread email; opens in Gmail, or becomes a task with the subject, sender and link.
struct MailRow: View {
    let message: Gmail.Message
    let store: Store
    @State private var hover = false
    @State private var made = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(message.from).font(.wave(14, .medium)).foregroundStyle(Theme.ink.opacity(0.6)).lineLimit(1)
                    Text(message.date.formatted(.relative(presentation: .named))).font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.4))
                }
                Text(message.subject).font(.wave(18, .medium)).tracking(-0.4).lineLimit(1)
                Text(message.snippet).font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            Button {
                let r = EKReminder(eventStore: store.ek)
                r.title = message.subject
                r.notes = "From \(message.from)\n\(message.snippet)"
                r.url = message.link
                r.calendar = store.ek.defaultCalendarForNewReminders()
                try? store.save(r)
                made = true
            } label: { Chip(text: made ? "Task added" : "Make a task", selected: made) }
            .buttonStyle(PressStyle())
            .disabled(made)
            Icon(hover ? "arrow-up-right" : "envelope-simple", size: 18, color: Theme.ink.opacity(0.6), weight: hover ? .bold : .fill)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .cardBlock()
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusBlock).fill(Theme.ink.opacity(hover ? 0.04 : 0)).allowsHitTesting(false))
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(message.link) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.2), value: hover)
    }
}

/// The experience row: `rounded-btn px-8 py-4 bg-ink/[0.04]`, violet with a long shadow when due today.
struct TaskRow: View {
    let reminder: EKReminder
    let store: Store
    var reload: () -> Void = {}
    @Environment(UI.self) private var ui
    @State private var hover = false

    var body: some View {
        let due = reminder.dueDate
        let today = due.map { Calendar.current.isDateInToday($0) } ?? false
        let overdue = due.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false
        let fg = today ? Theme.paper : Theme.ink
        HStack(spacing: 20) {
            Button(action: complete) {
                Circle().strokeBorder(fg.opacity(today ? 0.7 : 0.3), lineWidth: 1.5)
                    .background(Circle().fill(fg.opacity(hover ? 0.08 : 0)))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            if reminder.priority > 0 {
                Text(String(repeating: "!", count: reminder.priority == 1 ? 3 : reminder.priority == 5 ? 2 : 1))
                    .font(.wave(20, .semibold)).foregroundStyle(today ? Theme.paper : Theme.violet)
            }
            Text(reminder.title ?? "").font(.wave(20, .medium)).tracking(-0.5).lineLimit(1)
            if reminder.hasAlarms { Icon("bell", size: 14, color: fg.opacity(0.5)) }
            if reminder.hasRecurrenceRules { Icon("repeat", size: 14, color: fg.opacity(0.5)) }
            Spacer()
            Text(reminder.calendar.title).foregroundStyle(fg.opacity(today ? 0.8 : 0.5))
            if let due {
                Text(dueText(due, today: today))
                    .foregroundStyle(overdue ? Theme.danger : fg.opacity(today ? 0.8 : 0.5))
                    .monospacedDigit().frame(width: 130, alignment: .trailing)
            }
            MenuButton(onDark: today, items: [
                ("Edit", false, { ui.open(.editTask(reminder)) }),
                ("Delete", true, { try? store.delete(reminder); reload() }),
            ])
            .opacity(hover ? 1 : 0)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 32).padding(.vertical, 12)
        .background(today ? Theme.violet : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        .shadow(color: Theme.ink.opacity(today ? 0.25 : 0), radius: 16, x: 16, y: 24)
        .contentShape(Rectangle())
        .onTapGesture { ui.open(.editTask(reminder)) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }

    private func dueText(_ due: Date, today: Bool) -> String {
        let hasTime = reminder.dueDateComponents?.hour != nil
        if today { return hasTime ? due.formatted(date: .omitted, time: .shortened) : "Today" }
        let day = due.formatted(.dateTime.day().month(.abbreviated))
        return hasTime ? "\(day), \(due.formatted(date: .omitted, time: .shortened))" : day
    }

    private func complete() {
        reminder.isCompleted = true
        try? store.save(reminder)
        reload()
    }
}

/// Everything Reminders exposes through EventKit: title, notes, URL, date, time, alert, repeat, list, priority.
struct TaskEditor: View {
    let store: Store
    let reminder: EKReminder?
    @Environment(UI.self) private var ui
    @State private var title = ""
    @State private var notes = ""
    @State private var url = ""
    @State private var hasDate = false
    @State private var hasTime = false
    @State private var alert = false
    @State private var date = Date.now
    @State private var month = Date.now
    @State private var repeats: EKRecurrenceFrequency?
    @State private var list: EKCalendar?
    @State private var priority = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PanelTitle(text: reminder == nil ? "New task" : "Edit task")
                    Spacer()
                    if let reminder {
                        SecondaryButton(title: "Delete", danger: true) { try? store.delete(reminder); ui.close() }
                    }
                }
                VStack(spacing: 8) {
                    TextField("Title", text: $title).waveField()
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6).waveField()
                    TextField("URL", text: $url).waveField()
                }
                VStack(spacing: 8) {
                    Switch(title: "Date", isOn: $hasDate)
                    if hasDate {
                        MonthGrid(month: $month, selected: $date, eventDays: [])
                            .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
                        Switch(title: "Time", isOn: $hasTime)
                        if hasTime { TimeRow(date: $date) }
                        Switch(title: "Alert at the time", isOn: $alert)
                        Select(title: "Repeat", value: $repeats, options: [
                            (nil, "Never"), (.daily, "Daily"), (.weekly, "Weekly"), (.monthly, "Monthly"), (.yearly, "Yearly"),
                        ])
                    }
                }
                .padding(.top, 4)
                VStack(spacing: 8) {
                    if !store.lists.isEmpty {
                        Select(title: "List", value: $list, options: store.lists.map { ($0, $0.title) })
                    }
                    Select(title: "Priority", value: $priority, options: [(0, "None"), (9, "Low"), (5, "Medium"), (1, "High")])
                }
                PanelButtons(primary: reminder == nil ? "Add task" : "Save", disabled: title.isEmpty, action: save)
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 760)
        .panel(width: 480)
        .onAppear(perform: load)
    }

    private func load() {
        list = reminder?.calendar ?? store.ek.defaultCalendarForNewReminders() ?? store.lists.first
        guard let reminder else { return }
        title = reminder.title
        notes = reminder.notes ?? ""
        url = reminder.url?.absoluteString ?? ""
        priority = reminder.priority
        repeats = reminder.recurrenceRules?.first?.frequency
        alert = reminder.hasAlarms
        if let d = reminder.dueDate {
            hasDate = true
            hasTime = reminder.dueDateComponents?.hour != nil
            date = d
            month = d
        }
    }

    private func save() {
        let r = reminder ?? EKReminder(eventStore: store.ek)
        r.title = title
        r.notes = notes.isEmpty ? nil : notes
        r.url = url.isEmpty ? nil : URL(string: url)
        r.priority = priority
        if let list { r.calendar = list }
        if hasDate {
            let parts: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            let components = Calendar.current.dateComponents(parts, from: date)
            r.dueDateComponents = components
            r.startDateComponents = components
            r.recurrenceRules = repeats.map { [EKRecurrenceRule(recurrenceWith: $0, interval: 1, end: nil)] }
            let alarmDate = hasTime ? date : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            r.alarms = alert ? [EKAlarm(absoluteDate: alarmDate)] : nil
        } else {
            r.dueDateComponents = nil
            r.startDateComponents = nil
            r.recurrenceRules = nil
            r.alarms = nil
        }
        try? store.save(r)
        ui.close()
    }
}
