import SwiftUI
import SwiftData
import EventKit
import AppKit

/// Our own status item and popover: a borderless, transparent panel under the menu bar glyph, sized to its
/// SwiftUI content, closed by a click anywhere else. No system chrome at all.
enum StatusBar {
    private static var item: NSStatusItem?
    private static var panel: NSPanel?
    private static var monitor: Any?
    private static var resizeObserver: Any?
    private static var hiddenAt = Date.distantPast

    static func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(named: "MenuBarIcon")
        item.button?.image?.isTemplate = true
        item.button?.target = Trampoline.shared
        item.button?.action = #selector(Trampoline.toggle)
        self.item = item
    }

    static func toggle() {
        if let panel, panel.isVisible { hide(); return }
        // The outside-click monitor may have just closed it for this same click on the glyph: stay closed.
        if Date.now.timeIntervalSince(hiddenAt) < 0.3 { return }
        show()
    }

    static func show() {
        hide()
        let host = NSHostingView(rootView: MenuBarPanel().modelContainer(Database.container))
        host.sizingOptions = [.preferredContentSize]
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = host
        panel = p
        place()
        p.makeKeyAndOrderFront(nil)
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: p, queue: .main) { _ in place() }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let button = item?.button, let window = button.window,
               window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation) { return }
            hide()
        }
    }

    /// Centered under the glyph, top edge just below the menu bar, however tall the content gets.
    private static func place() {
        guard let panel, let button = item?.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrameOrigin(NSPoint(x: anchor.midX - panel.frame.width / 2, y: anchor.minY - panel.frame.height - 6))
    }

    static func hide() {
        if panel?.isVisible == true { hiddenAt = .now }
        panel?.orderOut(nil)
        panel = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
    }

    final class Trampoline: NSObject {
        static let shared = Trampoline()
        @objc func toggle() { StatusBar.toggle() }
    }
}

/// Compact Today behind the menu bar glyph: events, tasks to tick, habits to tap.
struct MenuBarPanel: View {
    @State private var store = Store()
    @Query(sort: \Habit.created) private var habits: [Habit]
    @AppStorage("theme") private var theme = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                LiveDot()
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6))
                Spacer()
                Button {
                    StatusBar.hide()
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                } label: { Chip(text: "Open Wave", selected: true) }.buttonStyle(PressStyle())
                Button("") { StatusBar.hide() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            }

            if !store.events.isEmpty {
                section("Events") {
                    ForEach(store.events.prefix(4), id: \.self) { e in
                        HStack(spacing: 12) {
                            Text(e.isAllDay ? "All day" : e.startDate.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(Theme.ink.opacity(0.5)).monospacedDigit().frame(width: 60, alignment: .leading)
                            Text(e.title ?? "").font(.wave(15, .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).cardBlock()
                    }
                }
            }

            section("Tasks") {
                if store.items.isEmpty {
                    Text("Nothing due.").foregroundStyle(Theme.ink.opacity(0.5)).padding(.horizontal, 14).padding(.vertical, 10)
                }
                ForEach(store.items.prefix(6)) { r in
                    HStack(spacing: 12) {
                        Button {
                            r.isCompleted = true
                            try? store.save(r)
                            Task { await store.fetch(.today) }
                        } label: { Circle().strokeBorder(Theme.ink.opacity(0.3), lineWidth: 1.5).frame(width: 18, height: 18) }.buttonStyle(.plain)
                        Text(r.title ?? "").font(.wave(15, .medium)).lineLimit(1)
                        Spacer()
                        if let d = r.dueDate, r.dueDateComponents?.hour != nil {
                            Text(d.formatted(date: .omitted, time: .shortened)).font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).cardBlock()
                }
            }

            if !habits.isEmpty {
                Text("Habits").font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6))
                VStack(spacing: 8) {
                    ForEach(habits) { HabitTile(habit: $0) }
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .font(.wave(15))
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(Theme.scheme(theme))
        .task { await store.load(); await store.fetch(.today); await store.fetchEvents() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await store.fetch(.today); await store.fetchEvents() }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.wave(14)).foregroundStyle(Theme.ink.opacity(0.6))
            VStack(spacing: 4) { content() }.cardFrame()
        }
    }
}

/// HabitKit-style tile, in Wave's surfaces: icon square, name and streak, big done button, dense grid.
struct HabitTile: View {
    let habit: Habit

    var body: some View {
        let done = habit.isDone(.now)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Icon(habit.icon, size: 20, color: habit.tint, weight: .fill)
                    .frame(width: 40, height: 40)
                    .background(habit.tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).font(.wave(15, .semibold)).lineLimit(1)
                    Text(habit.streak == 0 ? "No streak yet" : "\(habit.streak) day streak").font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.5))
                }
                Spacer(minLength: 8)
                Button { habit.toggle(.now) } label: {
                    ZStack {
                        if done {
                            RoundedRectangle(cornerRadius: 12).fill(habit.tint)
                            Icon("check", size: 18, color: Color(white: 0.1))
                        } else {
                            Circle().strokeBorder(habit.tint.opacity(0.35), lineWidth: 3).padding(3)
                            Icon("plus", size: 16, color: habit.tint)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(PressStyle())
            }
            HabitMiniGrid(habit: habit, width: 340 - 24)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
        .animation(.easeOut(duration: 0.2), value: done)
    }
}

/// The habit's history in one Canvas draw call: as many weeks as fit the width, done cells in the habit's
/// color, missed days in the same color dimmed, nothing after today.
struct HabitMiniGrid: View {
    let habit: Habit
    let width: CGFloat
    private let cell: CGFloat = 10
    private let gap: CGFloat = 3

    var body: some View {
        let pitch = cell + gap
        let weeks = max(1, Int((width + gap) / pitch))
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekEnd = cal.date(byAdding: .day, value: 7 - cal.component(.weekday, from: today), to: today)!
        let start = cal.date(byAdding: .day, value: 1 - weeks * 7, to: weekEnd)!
        let done = Set(habit.days.map { cal.startOfDay(for: $0) })
        let tint = habit.tint
        let dim = habit.tint.opacity(0.22)
        Canvas { context, _ in
            for w in 0..<weeks {
                for d in 0..<7 {
                    let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                    if day > today { continue }
                    let rect = CGRect(x: CGFloat(w) * pitch, y: CGFloat(d) * pitch, width: cell, height: cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(done.contains(day) ? tint : dim))
                }
            }
        }
        .frame(width: CGFloat(weeks) * pitch - gap, height: 7 * pitch - gap)
    }
}
