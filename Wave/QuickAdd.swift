import SwiftUI
import AppKit
import SwiftData
import EventKit
import Carbon.HIToolbox

/// ⌥Space anywhere: a floating capture panel at the bottom centre of the screen, shaped like a chat box.
/// Type, pick Task or Reminder, set everything the editors offer, Return sends. Carbon hot keys need no permission.
enum QuickAdd {
    private static var hotKey: EventHotKeyRef?
    private static var panel: NSPanel?
    private static var monitor: Any?
    private static var resizeObserver: Any?

    static func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            DispatchQueue.main.async { QuickAdd.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: 0x57415645, id: 1)   // 'WAVE'
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetEventDispatcherTarget(), 0, &hotKey)
    }

    static func toggle() {
        if let panel, panel.isVisible { hide(); return }
        show()
    }

    static func show() {
        hide()
        let host = NSHostingView(rootView: CapturePanel(close: hide))
        host.sizingOptions = [.preferredContentSize]
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                         styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        panel = p
        place()
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(host)
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: p, queue: .main) { _ in place() }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in hide() }
    }

    /// Bottom centre of the screen the mouse is on, 24pt above the Dock.
    private static func place() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 24))
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The chat box, repurposed: what you sent this session on top, the composer below with the kind picker and
/// every option a task or reminder can carry.
struct CapturePanel: View {
    let close: () -> Void
    @State private var text = ""
    @State private var sent: [String] = []
    @State private var asTodo = true
    @State private var kindOpen = false
    @State private var options = false
    @State private var note = ""
    @State private var hasDate = false
    @State private var hasTime = false
    @State private var alert = false
    @State private var date = Date.now
    @State private var month = Date.now
    @State private var repeats: EKRecurrenceFrequency?
    @State private var list: EKCalendar?
    @State private var priority = 0
    @State private var store = Store()
    @FocusState private var focused: Bool
    @AppStorage("theme") private var theme = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sent.isEmpty {
                Text("What needs doing?").font(.wave(15)).foregroundStyle(Theme.ink.opacity(0.4)).padding(.horizontal, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(sent.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 10) {
                            Icon("check", size: 12, color: Theme.brand)
                            Text(item).font(.wave(15, .medium)).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }

            // Composer
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    TextField(asTodo ? "New task" : "New reminder", text: $text)
                        .textFieldStyle(.plain).font(.wave(18, .medium)).focused($focused).onSubmit(send)
                    Button(action: send) {
                        Icon("arrow-up", size: 16, color: Theme.paper)
                            .frame(width: 34, height: 34)
                            .background(text.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.ink.opacity(0.3) : Theme.ink, in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: 8) {
                    Button { withAnimation(.easeOut(duration: 0.2)) { kindOpen.toggle() } } label: {
                        HStack(spacing: 6) {
                            Text(asTodo ? "Task" : "Reminder").font(.wave(14, .medium))
                            Icon("caret-down", size: 11, color: Theme.ink.opacity(0.6)).rotationEffect(.degrees(kindOpen ? 180 : 0))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressStyle())
                    quick("Today", on: hasDate && Calendar.current.isDateInToday(date)) { setDay(.now) }
                    quick("Tomorrow", on: hasDate && Calendar.current.isDateInTomorrow(date)) { setDay(Calendar.current.date(byAdding: .day, value: 1, to: .now)!) }
                    Button { withAnimation(.easeOut(duration: 0.2)) { options.toggle() } } label: {
                        HStack(spacing: 6) {
                            Icon("sliders-horizontal", size: 13, color: options ? Theme.paper : Theme.ink)
                            Text(options ? "Less" : "More").font(.wave(14, .medium))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(options ? Theme.ink : Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(options ? Theme.paper : Theme.ink)
                    }
                    .buttonStyle(PressStyle())
                    Spacer()
                    Text("⌥ Space").font(.wave(12)).foregroundStyle(Theme.ink.opacity(0.35))
                }
                if kindOpen {
                    VStack(spacing: 2) {
                        kindRow("Task", "Check it off and it is gone. Stays in Wave.", true)
                        kindRow("Reminder", "Date, alert, repeat. Synced with your iPhone.", false)
                    }
                    .padding(6).background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if options {
                    VStack(spacing: 8) {
                        TextField(asTodo ? "Note" : "Notes", text: $note, axis: .vertical).lineLimit(1...4).waveField()
                        Switch(title: "Date", isOn: $hasDate)
                        if hasDate {
                            MonthGrid(month: $month, selected: $date, eventDays: [])
                                .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
                        }
                        if !asTodo {
                            if hasDate {
                                Switch(title: "Time", isOn: $hasTime)
                                if hasTime { TimeRow(date: $date) }
                                Switch(title: "Alert at the time", isOn: $alert)
                                Select(title: "Repeat", value: $repeats, options: [
                                    (nil, "Never"), (.daily, "Daily"), (.weekly, "Weekly"), (.monthly, "Monthly"), (.yearly, "Yearly"),
                                ])
                            }
                            if !store.lists.isEmpty { Select(title: "List", value: $list, options: store.lists.map { ($0, $0.title) }) }
                            Select(title: "Priority", value: $priority, options: [(0, "None"), (9, "Low"), (5, "Medium"), (1, "High")])
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.ink.opacity(0.08)))
        }
        .padding(10)
        .frame(width: 520)
        .background(Theme.surface.opacity(0.0001))
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.ink.opacity(0.06)))
        .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 48)
        .font(.wave(16))
        .foregroundStyle(Theme.ink)
        .tint(Theme.violet)
        .preferredColorScheme(Theme.scheme(theme))
        .onAppear { Task { await store.load(); list = store.ek.defaultCalendarForNewReminders() } }
        .task {
            // The panel becomes key a beat after the view appears; focus once it has.
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(60))
                focused = true
            }
        }
        .onExitCommand(perform: close)
        .animation(.spring(duration: 0.3, bounce: 0), value: sent.count)
    }

    private func quick(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon("calendar-blank", size: 13, color: on ? Theme.onAccent : Theme.ink)
                Text(title).font(.wave(14, .medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
            .background(on ? Theme.violet : Theme.chip, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressStyle())
    }

    private func kindRow(_ title: String, _ detail: String, _ todo: Bool) -> some View {
        Button { asTodo = todo; withAnimation(.easeOut(duration: 0.2)) { kindOpen = false } } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.wave(15, .medium))
                    Text(detail).font(.wave(13)).foregroundStyle(asTodo == todo ? Theme.paper.opacity(0.7) : Theme.ink.opacity(0.5))
                }
                Spacer()
                if asTodo == todo { Icon("check", size: 12, color: Theme.paper) }
            }
            .foregroundStyle(asTodo == todo ? Theme.paper : Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(asTodo == todo ? Theme.ink : Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setDay(_ day: Date) {
        if hasDate, Calendar.current.isDate(date, inSameDayAs: day) { hasDate = false; return }
        hasDate = true
        date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        month = date
    }

    private func send() {
        let title = text.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        if asTodo {
            let context = ModelContext(Database.container)
            context.insert(Todo(title: title, note: note, due: hasDate ? Calendar.current.startOfDay(for: date) : nil))
            try? context.save()
        } else {
            let r = EKReminder(eventStore: store.ek)
            r.title = title
            r.notes = note.isEmpty ? nil : note
            r.priority = priority
            r.calendar = list ?? store.ek.defaultCalendarForNewReminders()
            if hasDate {
                let parts: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
                let components = Calendar.current.dateComponents(parts, from: date)
                r.dueDateComponents = components
                r.startDateComponents = components
                r.recurrenceRules = repeats.map { [EKRecurrenceRule(recurrenceWith: $0, interval: 1, end: nil)] }
                r.alarms = alert ? [EKAlarm(absoluteDate: hasTime ? date : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date)] : nil
            }
            try? store.save(r)
        }
        sent.append(title)
        text = ""
        note = ""
        hasDate = false
        hasTime = false
        alert = false
        repeats = nil
        priority = 0
        withAnimation(.easeOut(duration: 0.2)) { options = false }
        focused = true
    }
}
