import AppIntents
import SwiftData

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Adds a task to Wave's to-do list.")

    @Parameter(title: "Title", requestValueDialog: "What is the task?")
    var title: String

    static var parameterSummary: some ParameterSummary { Summary("Add task \(\.$title)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(Database.container)
        context.insert(Todo(title: title))
        try context.save()
        return .result(dialog: IntentDialog("Added \(title)."))
    }
}

struct AddReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Reminder"
    static let description = IntentDescription("Adds a reminder to Apple Reminders through Wave.")

    @Parameter(title: "Title", requestValueDialog: "What should I remind you of?")
    var title: String

    static var parameterSummary: some ParameterSummary { Summary("Add reminder \(\.$title)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store()
        await store.load()
        guard store.authorized else { return .result(dialog: "Wave needs Reminders access first.") }
        try store.add(title, to: nil)
        return .result(dialog: IntentDialog("Reminder added: \(title)."))
    }
}

struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Note"
    static let description = IntentDescription("Creates a note in Apple Notes through Wave.")

    @Parameter(title: "Title", requestValueDialog: "What is the note called?")
    var title: String
    @Parameter(title: "Text", default: "")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Add note \(\.$title)") { \.$text } }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(Database.container)
        context.insert(Note(title: title, text: text))
        try context.save()
        return .result(dialog: IntentDialog("Saved \(title) in Wave."))
    }
}

struct WaveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTaskIntent(), phrases: ["Add a task in \(.applicationName)", "New \(.applicationName) task"],
                    shortTitle: "Add task", systemImageName: "plus")
        AppShortcut(intent: AddReminderIntent(), phrases: ["Add a reminder in \(.applicationName)", "Remind me in \(.applicationName)"],
                    shortTitle: "Add reminder", systemImageName: "bell")
        AppShortcut(intent: AddNoteIntent(), phrases: ["Add a note in \(.applicationName)", "New \(.applicationName) note"],
                    shortTitle: "Add note", systemImageName: "note.text")
    }
}
