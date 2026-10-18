import SwiftUI
import EventKit

struct ContentView: View {
    @State private var reminders = Reminders()
    @State private var selection: Selection? = .today
    @State private var editing: EKReminder?
    @State private var newTitle = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Today", systemImage: "sun.max").tag(Selection.today)
                Section("Lists") {
                    ForEach(reminders.lists, id: \.calendarIdentifier) { list in
                        Label(list.title, systemImage: "list.bullet").tag(Selection.list(list))
                    }
                }
            }
        } detail: {
            if !reminders.authorized {
                ContentUnavailableView("Reminders access needed", systemImage: "lock",
                    description: Text("Allow Wave in System Settings > Privacy & Security > Reminders."))
            } else {
                List {
                    ForEach(reminders.items) { r in
                        HStack(alignment: .top) {
                            Button { complete(r) } label: { Image(systemName: "circle") }
                                .buttonStyle(.plain)
                            VStack(alignment: .leading) {
                                Text(r.title)
                                if let d = r.dueDate {
                                    Text(d, format: .dateTime.day().month().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(d < .now ? .red : .secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = r }
                    }
                    TextField("New task", text: $newTitle).onSubmit(add)
                }
                .navigationTitle(title)
            }
        }
        .task { await reminders.load(); await refresh() }
        .onChange(of: selection) { Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await refresh() } }
        .sheet(item: $editing) { ReminderEditor(reminder: $0, reminders: reminders) }
    }

    private var title: String {
        if case .list(let l) = selection { l.title } else { "Today" }
    }

    private func refresh() async { await reminders.fetch(selection ?? .today) }

    private func add() {
        guard !newTitle.isEmpty else { return }
        let list: EKCalendar? = if case .list(let l) = selection { l } else { nil }
        try? reminders.add(newTitle, to: list)
        newTitle = ""
        Task { await refresh() }
    }

    private func complete(_ r: EKReminder) {
        r.isCompleted = true
        try? reminders.save(r)
        Task { await refresh() }
    }
}

struct ReminderEditor: View {
    let reminder: EKReminder
    let reminders: Reminders
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDue = false
    @State private var due = Date.now
    @State private var repeats: EKRecurrenceFrequency?

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
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
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
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
        try? reminders.save(reminder)
        dismiss()
    }
}
