import SwiftData
import Foundation

/// One local SwiftData store for everything Wave owns: habits, clients, notes. Shared by the app and the CLI.
enum Database {
    static let container: ModelContainer = {
        let url = URL.applicationSupportDirectory.appending(path: "Wave/wave.store")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try! ModelContainer(for: Habit.self, Client.self, Note.self, configurations: ModelConfiguration(url: url))
    }()
}
