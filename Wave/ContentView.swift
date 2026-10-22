import SwiftUI
import EventKit
import SwiftData

enum Page: String, CaseIterable {
    case home = "Home", today = "Tasks", calendar = "Calendar", habits = "Habits", notes = "Notes"
    case finances = "Finances", clients = "Clients", review = "Review"
}

struct ContentView: View {
    @State private var ui = UI.shared
    @State private var store = Store()
    @State private var finance = Finance()
    @State private var list: EKCalendar?
    @AppStorage("theme") private var theme = "system"

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                NavBar(button: buttonTitle, icon: ui.page == .finances ? "arrows-clockwise" : "plus", action: primaryAction)
                ScrollView {
                    Group {
                        switch ui.page {
                        case .home: HomePage(store: store, finance: finance)
                        case .today: TasksPage(store: store, list: $list)
                        case .calendar: CalendarPage(store: store)
                        case .habits: HabitsPage()
                        case .notes: NotesPage()
                        case .finances: FinancePage(finance: finance)
                        case .clients: ClientsPage(store: store, finance: finance)
                        case .review: ReviewPage(store: store, finance: finance)
                        }
                    }
                    .id(ui.page)
                    .frame(maxWidth: 1200)
                    .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 160)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
            }
            .overlay(alignment: .bottom) {
                Dock(items: Page.allCases.map { page in
                    DockItem(id: page.rawValue, label: page.rawValue, icon: page.icon, active: ui.page == page) { ui.page = page }
                } + [
                    DockItem(id: "|", label: "", icon: "", action: {}),
                    DockItem(id: "search", label: "Search ⌘K", icon: "magnifying-glass") { ui.open(.palette) },
                    DockItem(id: "settings", label: "Settings ⌘,", icon: "gear-six") { ui.open(.settings) },
                ])
                .padding(.bottom, 24)
            }
            ModalHost(store: store, finance: finance)
        }
        .environment(ui)
        .background(CanvasBackground())
        .font(.wave(16))
        .foregroundStyle(Theme.ink)
        .tint(Theme.violet)
        .preferredColorScheme(Theme.scheme(theme))
        .frame(minWidth: 900, minHeight: 600)
        .task { await store.load(); await refresh() }
        .onChange(of: list) { Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await refresh() } }
    }

    private var buttonTitle: String {
        switch ui.page {
        case .home, .today, .review: "New"
        case .calendar: "New event"
        case .habits: "New habit"
        case .notes: "New note"
        case .finances: "Refresh"
        case .clients: "New client"
        }
    }

    private func primaryAction() {
        switch ui.page {
        case .finances: Task { await finance.refresh() }
        case .notes: ui.requestNewNote()
        default: ui.open(ui.newItem)
        }
    }

    private func refresh() async {
        let selection: Selection = list.map { .list($0) } ?? .today
        await store.fetch(selection)
        if list == nil { await store.fetchEvents() }
    }
}

/// Brand left, the ink button right. Page links live in the dock at the bottom. Sits under the hidden title bar.
struct NavBar: View {
    let button: String
    let icon: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Wave").font(.wave(20, .semibold)).tracking(-0.5)
            Spacer()
            PrimaryButton(title: button, icon: icon, action: action)
        }
        .padding(.leading, 96).padding(.trailing, 40)
        .frame(height: 72)
    }
}

/// Two kinds of things to check off: Wave's own tasks, and the Reminders mirror below them.
struct TasksPage: View {
    let store: Store
    @Binding var list: EKCalendar?
    @Environment(UI.self) private var ui
    @Environment(\.modelContext) private var context
    @State private var newTitle = ""
    @State private var newReminder = ""
    @State private var todos: [Todo] = []
    @State private var done: [Todo] = []
    @State private var showDone = false
    @State private var gmail = Gmail.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { LiveDot(); Eyebrow(text: "Tasks") }.rise()
            Heading(muted: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()) + ".", strong: summary)
                .padding(.top, 20).rise(0.05)

            // Tasks: Wave's own list.
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "To do")
                Spacer()
                if !done.isEmpty {
                    Button { showDone.toggle() } label: { Chip(text: showDone ? "Hide done" : "Done · \(done.count)", selected: showDone) }.buttonStyle(PressStyle())
                }
            }
            .padding(.top, 56).rise(0.1)
            LazyVStack(spacing: 12) {
                ForEach(todos) { todo in TodoRow(todo: todo, reload: reload).rise(0.15) }
                if showDone {
                    ForEach(done) { todo in TodoRow(todo: todo, reload: reload) }
                }
                HStack(spacing: 16) {
                    Icon("plus", size: 16, color: Theme.ink.opacity(0.4))
                    TextField("New task, press Return", text: $newTitle).textFieldStyle(.plain).font(.wave(20, .medium)).onSubmit(addTodo)
                }
                .padding(.horizontal, 32).padding(.vertical, 16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                .rise(0.2)
            }
            .padding(.top, 20)

            // Reminders: Apple's, with dates, alerts and repeats.
            HStack(spacing: 8) {
                Eyebrow(text: "Reminders")
                Spacer()
                chip("Due", nil)
                ForEach(store.lists, id: \.calendarIdentifier) { chip($0.title, $0) }
            }
            .padding(.top, 64).rise(0.2)
            if !store.authorized {
                Text("Allow Wave in System Settings > Privacy & Security > Reminders.")
                    .foregroundStyle(Theme.ink.opacity(0.6)).padding(.top, 20)
            }
            LazyVStack(spacing: 12) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { i, r in
                    TaskRow(reminder: r, store: store, reload: reloadReminders).rise(0.25 + Double(min(i, 8)) * 0.05)
                }
                HStack(spacing: 16) {
                    Icon("plus", size: 16, color: Theme.ink.opacity(0.4))
                    TextField("New reminder, press Return", text: $newReminder).textFieldStyle(.plain).font(.wave(20, .medium)).onSubmit(addReminder)
                }
                .padding(.horizontal, 32).padding(.vertical, 16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                .rise(0.3)
            }
            .padding(.top, 20)

            if gmail.connected {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(text: "Inbox")
                    Spacer()
                    if gmail.loading { Spinner() } else {
                        Button { Task { await gmail.load() } } label: { Chip(text: "Refresh") }.buttonStyle(PressStyle())
                    }
                }
                .padding(.top, 64).rise(0.15)
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
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in reload() }
        .task { if gmail.connected, gmail.messages.isEmpty { await gmail.load() } }
    }

    private var summary: String {
        let t = "\(todos.count) task\(todos.count == 1 ? "" : "s")"
        let r = "\(store.items.count) reminder\(store.items.count == 1 ? "" : "s")"
        return "\(t) to do, \(r)\(list == nil ? " due" : " in \(list!.title)")."
    }

    private func chip(_ title: String, _ calendar: EKCalendar?) -> some View {
        Button { list = calendar } label: { Chip(text: title, selected: list == calendar) }.buttonStyle(PressStyle())
    }

    private func reload() {
        todos = Todo.open(context)
        done = Todo.recentlyDone(context)
    }

    private func reloadReminders() { Task { await store.fetch(list.map { .list($0) } ?? .today) } }

    private func addTodo() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        context.insert(Todo(title: title))
        try? context.save()
        newTitle = ""
        reload()
    }

    private func addReminder() {
        guard !newReminder.isEmpty else { return }
        try? store.add(newReminder, to: list)
        newReminder = ""
        reloadReminders()
    }
}

/// Same row as a reminder, for Wave's own task: check and it fades out; done ones show struck through.
struct TodoRow: View {
    let todo: Todo
    var reload: () -> Void = {}
    @Environment(UI.self) private var ui
    @Environment(\.modelContext) private var context
    @State private var hover = false
    @State private var checking = false

    var body: some View {
        let isDone = todo.done != nil
        let today = todo.due.map { Calendar.current.isDateInToday($0) } ?? false
        let overdue = todo.due.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false
        let fg = today && !isDone ? Theme.onAccent : Theme.ink
        HStack(spacing: 20) {
            Button(action: toggle) {
                ZStack {
                    Circle().strokeBorder(fg.opacity(today ? 0.7 : 0.3), lineWidth: 1.5)
                    if isDone || checking { Circle().fill(Theme.brand); Icon("check", size: 12, color: .white) }
                }
                .frame(width: 22, height: 22)
                .padding(6)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Text(todo.title).font(.wave(20, .medium)).tracking(-0.5).lineLimit(1).strikethrough(isDone, color: fg.opacity(0.5))
                .opacity(isDone ? 0.5 : 1)
            if !todo.note.isEmpty { Icon("note", size: 13, color: fg.opacity(0.5)) }
            Spacer()
            if let due = todo.due {
                Text(today ? "Today" : due.formatted(.dateTime.day().month(.abbreviated)))
                    .foregroundStyle(overdue && !isDone ? Theme.danger : fg.opacity(today ? 0.8 : 0.5)).frame(width: 130, alignment: .trailing)
            }
            MenuButton(onDark: today && !isDone, color: today && !isDone ? Theme.onAccent : nil, items: [
                ("Edit", false, { ui.open(.editTodo(todo)) }),
                ("Delete", true, { context.delete(todo); try? context.save(); reload() }),
            ])
            .opacity(hover ? 1 : 0)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 32).padding(.vertical, 12)
        .background(today && !isDone ? Theme.violet : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        .shadow(color: Theme.shadow.opacity(today && !isDone ? 0.25 : 0), radius: 16, x: 16, y: 24)
        .contentShape(Rectangle())
        .onTapGesture { ui.open(.editTodo(todo)) }
        .onHover { hover = $0 }
        .opacity(checking ? 0 : 1)
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(.easeOut(duration: 0.35), value: checking)
    }

    private func toggle() {
        if todo.done != nil { todo.done = nil; try? context.save(); reload(); return }
        checking = true
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            todo.done = .now
            try? context.save()
            reload()
        }
    }
}

/// Title, note and an optional date. Nothing else: that is what makes it a task and not a reminder.
struct TodoEditor: View {
    let todo: Todo?
    var kindPicker: AnyView? = nil
    @Environment(UI.self) private var ui
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var note = ""
    @State private var hasDate = false
    @State private var date = Date.now
    @State private var month = Date.now
    @State private var editingDate = false

    var body: some View {
        FitScroll(max: 760) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PanelTitle(text: todo == nil ? "New task" : "Edit task")
                    Spacer()
                    if let todo { HoldButton(compact: true) { context.delete(todo); try? context.save(); ui.close() } }
                }
                if let kindPicker { kindPicker }
                VStack(spacing: 8) {
                    TextField("Title", text: $title).waveField()
                    TextField("Note", text: $note, axis: .vertical).lineLimit(2...6).waveField()
                }
                VStack(spacing: 8) {
                    Switch(title: "Date", isOn: $hasDate)
                    if hasDate {
                        if todo != nil, !editingDate {
                            DateSummary(date: date, editing: $editingDate)
                        } else {
                            if todo != nil { DateSummary(date: date, editing: $editingDate) }
                            MonthGrid(month: $month, selected: $date, eventDays: [])
                                .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
                        }
                    }
                }
                PanelButtons(primary: todo == nil ? "Add task" : "Save", disabled: title.isEmpty, action: save)
            }
        }
        .panel(width: 480)
        .onAppear {
            guard let todo else { return }
            title = todo.title; note = todo.note
            if let d = todo.due { hasDate = true; date = d; month = d }
        }
    }

    private func save() {
        let t = todo ?? Todo(title: title)
        t.title = title
        t.note = note
        t.due = hasDate ? Calendar.current.startOfDay(for: date) : nil
        if todo == nil { context.insert(t) }
        try? context.save()
        ui.close()
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
        let fg = today ? Theme.onAccent : Theme.ink
        HStack(spacing: 20) {
            Button(action: complete) {
                Circle().strokeBorder(fg.opacity(today ? 0.7 : 0.3), lineWidth: 1.5)
                    .background(Circle().fill(fg.opacity(hover ? 0.08 : 0)))
                    .frame(width: 22, height: 22)
                    .padding(6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            if reminder.priority > 0 {
                Text(String(repeating: "!", count: reminder.priority == 1 ? 3 : reminder.priority == 5 ? 2 : 1))
                    .font(.wave(20, .semibold)).foregroundStyle(today ? Theme.onAccent : Theme.violet)
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
            MenuButton(onDark: today, color: today ? Theme.onAccent : nil, items: [
                ("Edit", false, { ui.open(.editTask(reminder)) }),
                ("Delete", true, { try? store.delete(reminder); reload() }),
            ])
            .opacity(hover ? 1 : 0)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 32).padding(.vertical, 12)
        .background(today ? Theme.violet : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        .shadow(color: Theme.shadow.opacity(today ? 0.25 : 0), radius: 16, x: 16, y: 24)
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

/// New item: pick Task or Reminder on top. Editing an existing reminder skips the choice.
struct TaskEditor: View {
    let store: Store
    let reminder: EKReminder?
    @State private var asTodo = true
    var body: some View {
        if reminder == nil, asTodo {
            TodoEditor(todo: nil, kindPicker: picker)
        } else {
            ReminderEditor(store: store, reminder: reminder, kindPicker: reminder == nil ? picker : nil)
        }
    }
    private var picker: AnyView {
        AnyView(HStack(spacing: 8) {
            Button { asTodo = true } label: { Chip(text: "Task", selected: asTodo) }.buttonStyle(PressStyle())
            Button { asTodo = false } label: { Chip(text: "Reminder", selected: !asTodo) }.buttonStyle(PressStyle())
            Text(asTodo ? "Check it off and it is gone." : "Date, alert, repeat, synced with your iPhone.").font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.5))
        })
    }
}

/// Everything Reminders exposes through EventKit: title, notes, URL, date, time, alert, repeat, list, priority.
struct ReminderEditor: View {
    let store: Store
    let reminder: EKReminder?
    var kindPicker: AnyView? = nil
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
    @State private var editingDate = false

    var body: some View {
        FitScroll(max: 760) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PanelTitle(text: reminder == nil ? "New reminder" : "Edit reminder")
                    Spacer()
                    if let reminder {
                        HoldButton(compact: true) { try? store.delete(reminder); ui.close() }
                    }
                }
                if let kindPicker { kindPicker }
                VStack(spacing: 8) {
                    TextField("Title", text: $title).waveField()
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6).waveField()
                    TextField("URL", text: $url).waveField()
                }
                VStack(spacing: 8) {
                    Switch(title: "Date", isOn: $hasDate)
                    if hasDate {
                        if reminder != nil { DateSummary(date: date, editing: $editingDate) }
                        if reminder == nil || editingDate {
                            MonthGrid(month: $month, selected: $date, eventDays: [])
                                .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
                        }
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
                PanelButtons(primary: reminder == nil ? "Add reminder" : "Save", disabled: title.isEmpty, action: save)
            }
        }
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
