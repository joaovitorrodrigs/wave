import SwiftUI
import SwiftData

@main struct WaveApp: App {
    init() {
        Theme.registerFont()
        #if DEBUG
        Habit.selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Habit.container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 860)
        Settings { SettingsView() }
    }
}
