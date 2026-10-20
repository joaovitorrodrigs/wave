import SwiftUI
import SwiftData
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusBar.install()
        QuickAdd.install()
        Morning.start()
    }
}

@main struct WaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

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
        .modelContainer(Database.container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Item") { if UI.shared.page == .notes { UI.shared.requestNewNote() } else { UI.shared.open(UI.shared.newItem) } }.keyboardShortcut("n")
                Button("Search") { UI.shared.open(.palette) }.keyboardShortcut("k")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { UI.shared.open(.settings) }.keyboardShortcut(",")
            }
            CommandMenu("Go") {
                ForEach(Array(Page.allCases.enumerated()), id: \.offset) { i, page in
                    Button(page.rawValue) { UI.shared.page = page }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
        }
    }
}
