import SwiftUI
import SwiftData

@main struct WaveApp: App {
    init() {
        #if DEBUG
        Habit.selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Habit.container)
    }
}
