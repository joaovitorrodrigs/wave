import SwiftUI
import EventKit

enum Page: String, CaseIterable {
    case today = "Today", habits = "Habits", notes = "Notes", finances = "Finances"
}

struct ContentView: View {
    @State private var store = Store()
    @State private var notes = Notes()
    @State private var finance = Finance()
    @State private var page: Page = .today
    @State private var list: EKCalendar?
    @State private var editing: EKReminder?
    @State private var addingTask = false
    @State private var addingHabit = false
    @State private var addingNote = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(page: $page, button: buttonTitle, icon: buttonIcon, action: primaryAction)
            ScrollView {
                Group {
                    switch page {
                    case .today: TodayPage(store: store, list: $list, editing: $editing)
                    case .habits: HabitsPage(adding: $addingHabit)
                    case .notes: NotesPage(notes: notes)
                    case .finances: FinancePage(finance: finance)
                    }
                }
                .id(page)
                .frame(maxWidth: 1200)
                .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 96)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.paper)
        .font(.wave(16))
        .foregroundStyle(Theme.ink)
        .tint(Theme.violet)
        .preferredColorScheme(.light)
        .frame(minWidth: 900, minHeight: 600)
        .task { await store.load(); await refresh() }
        .onChange(of: list) { Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await refresh() } }
        .sheet(item: $editing) { ReminderEditor(reminder: $0, store: store) }
        .sheet(isPresented: $addingTask) { NewTaskSheet(store: store, list: list) }
        .sheet(isPresented: $addingHabit) { HabitEditor(habit: nil) }
        .sheet(isPresented: $addingNote) { NoteEditor(notes: notes) }
    }

    private var buttonTitle: String {
        switch page {
        case .today: "New task"
        case .habits: "New habit"
        case .notes: "New note"
        case .finances: "Refresh"
        }
    }

    private var buttonIcon: String { page == .finances ? "arrow.clockwise" : "plus" }

    private func primaryAction() {
        switch page {
        case .today: addingTask = true
        case .habits: addingHabit = true
        case .notes: addingNote = true
        case .finances: Task { await finance.refresh() }
        }
    }

    private func refresh() async {
        let selection: Selection = list.map { .list($0) } ?? .today
        await store.fetch(selection)
        if list == nil { await store.fetchEvents() }
    }
}

/// The site's navbar: brand left, links centered, ink button right. Sits under the hidden title bar.
struct NavBar: View {
    @Binding var page: Page
    let button: String
    let icon: String
    let action: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 32) {
                ForEach(Page.allCases, id: \.self) { p in
                    Button { page = p } label: {
                        Text(p.rawValue).font(.wave(16)).foregroundStyle(Theme.ink.opacity(page == p ? 1 : 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text("Wave").font(.wave(20, .semibold)).tracking(-0.5)
                Spacer()
                PrimaryButton(title: button, icon: icon, action: action)
            }
        }
        .padding(.leading, 96).padding(.trailing, 40)
        .frame(height: 72)
    }
}

struct TodayPage: View {
    let store: Store
    @Binding var list: EKCalendar?
    @Binding var editing: EKReminder?
    @State private var newTitle = ""

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

            Eyebrow(text: list == nil ? "Tasks" : list!.title).padding(.top, 56).rise(0.2)
            LazyVStack(spacing: 12) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { i, r in
                    TaskRow(reminder: r, complete: { complete(r) }, open: { editing = r })
                        .rise(0.25 + Double(min(i, 8)) * 0.05)
                }
                HStack(spacing: 16) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink.opacity(0.4))
                    TextField("New task, press Return", text: $newTitle).textFieldStyle(.plain).font(.wave(20, .medium)).onSubmit(add)
                }
                .padding(.horizontal, 32).padding(.vertical, 16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                .rise(0.3)
            }
            .padding(.top, 20)
        }
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

    private func add() {
        guard !newTitle.isEmpty else { return }
        try? store.add(newTitle, to: list)
        newTitle = ""
        Task { await store.fetch(list.map { .list($0) } ?? .today) }
    }

    private func complete(_ r: EKReminder) {
        r.isCompleted = true
        try? store.save(r)
        Task { await store.fetch(list.map { .list($0) } ?? .today) }
    }
}

/// The experience row: `rounded-btn px-8 py-4 bg-ink/[0.04]`, violet with a long shadow when due today.
struct TaskRow: View {
    let reminder: EKReminder
    let complete: () -> Void
    let open: () -> Void
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
            Text(reminder.title ?? "").font(.wave(20, .medium)).tracking(-0.5).lineLimit(1)
            Spacer()
            Text(reminder.calendar.title).foregroundStyle(fg.opacity(today ? 0.8 : 0.5))
            if let due {
                Text(due.formatted(today ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated).hour().minute()))
                    .foregroundStyle(overdue ? Theme.violet : fg.opacity(today ? 0.8 : 0.5))
                    .monospacedDigit().frame(width: 130, alignment: .trailing)
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 32).padding(.vertical, 16)
        .background(today ? Theme.violet : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        .shadow(color: Theme.ink.opacity(today ? 0.25 : 0), radius: 16, x: 16, y: 24)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hover = $0 }
    }
}

struct NewTaskSheet: View {
    let store: Store
    let list: EKCalendar?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDue = false
    @State private var due = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New task").font(.wave(26, .medium)).tracking(-0.6)
            TextField("What needs doing?", text: $title).waveField()
            Toggle("Due date", isOn: $hasDue).font(.wave(16))
            if hasDue { DatePicker("", selection: $due).labelsHidden() }
            HStack {
                SecondaryButton(title: "Cancel") { dismiss() }
                Spacer()
                PrimaryButton(title: "Add task", large: false) {
                    try? store.add(title, to: list, due: hasDue ? due : nil)
                    dismiss()
                }
                .disabled(title.isEmpty).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 440)
        .font(.wave(16))
        .background(Theme.paper)
    }
}

struct ReminderEditor: View {
    let reminder: EKReminder
    let store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDue = false
    @State private var due = Date.now
    @State private var repeats: EKRecurrenceFrequency?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit task").font(.wave(26, .medium)).tracking(-0.6)
            TextField("Title", text: $title).waveField()
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8).waveField()
            Toggle("Due date", isOn: $hasDue)
            if hasDue {
                DatePicker("Due", selection: $due)
                Picker("Repeat", selection: $repeats) {
                    Text("Never").tag(EKRecurrenceFrequency?.none)
                    Text("Daily").tag(EKRecurrenceFrequency?.some(.daily))
                    Text("Weekly").tag(EKRecurrenceFrequency?.some(.weekly))
                    Text("Monthly").tag(EKRecurrenceFrequency?.some(.monthly))
                    Text("Yearly").tag(EKRecurrenceFrequency?.some(.yearly))
                }
            }
            HStack {
                SecondaryButton(title: "Cancel") { dismiss() }
                Spacer()
                PrimaryButton(title: "Save", action: save).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 440)
        .font(.wave(16))
        .background(Theme.paper)
        .onAppear {
            title = reminder.title
            notes = reminder.notes ?? ""
            if let d = reminder.dueDate { hasDue = true; due = d }
            repeats = reminder.recurrenceRules?.first?.frequency
        }
    }

    private func save() {
        reminder.title = title
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.dueDateComponents = hasDue
            ? Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due) : nil
        reminder.recurrenceRules = (hasDue ? repeats : nil).map { [EKRecurrenceRule(recurrenceWith: $0, interval: 1, end: nil)] }
        try? store.save(reminder)
        dismiss()
    }
}
