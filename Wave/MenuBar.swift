import SwiftUI
import SwiftData
import EventKit

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
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                } label: { Chip(text: "Open Wave", selected: true) }.buttonStyle(PressStyle())
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
                Eyebrow(text: "Habits").font(.wave(14))
                FlowChips(habits: habits)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(CanvasBackground())
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

struct FlowChips: View {
    let habits: [Habit]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(habits) { habit in
                Button { habit.toggle(.now) } label: {
                    HStack(spacing: 6) {
                        Icon(habit.isDone(.now) ? "check" : habit.icon, size: 14, color: habit.isDone(.now) ? Theme.paper : Theme.ink.opacity(0.7), weight: habit.isDone(.now) ? .bold : .fill)
                        Text(habit.name).lineLimit(1)
                    }
                    .font(.wave(13)).padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(habit.isDone(.now) ? Theme.paper : Theme.ink.opacity(0.7))
                    .background(habit.isDone(.now) ? Theme.ink : Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}
