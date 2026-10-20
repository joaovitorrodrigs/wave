import SwiftUI
import AppKit
import Carbon.HIToolbox

/// ⌘⇧Space anywhere: a floating field that adds a task to Reminders. Carbon hot keys need no Accessibility permission.
enum QuickAdd {
    private static var hotKey: EventHotKeyRef?
    private static var panel: NSPanel?

    static func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            DispatchQueue.main.async { QuickAdd.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: 0x57415645, id: 1)   // 'WAVE'
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), id, GetEventDispatcherTarget(), 0, &hotKey)
    }

    static func toggle() {
        if let panel, panel.isVisible { hide(); return }
        show()
    }

    static func show() {
        hide()
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 180),
                         styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: QuickAddView(close: hide))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.maxY - f.height * 0.28))
        }
        panel = p
        p.makeKeyAndOrderFront(nil)
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct QuickAddView: View {
    let close: () -> Void
    @State private var text = ""
    @State private var store = Store()
    @FocusState private var focused: Bool
    @AppStorage("theme") private var theme = "system"

    var body: some View {
        HStack(spacing: 16) {
            Icon("plus", size: 20, color: Theme.ink.opacity(0.5))
            TextField("Add a task to Reminders. Return saves, Esc closes.", text: $text)
                .textFieldStyle(.plain).font(.wave(22, .medium)).focused($focused).onSubmit(submit)
            Button("") { close() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .shadow(color: Theme.shadow.opacity(0.3), radius: 16, x: 16, y: 24)
        .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 64)
        .font(.wave(16))
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(Theme.scheme(theme))
        .onAppear { focused = true; Task { await store.load() } }
        .onExitCommand(perform: close)
    }

    private func submit() {
        let title = text.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        Task {
            if !store.authorized { await store.load() }
            try? store.add(title, to: nil)
            text = ""
            close()
        }
    }
}
