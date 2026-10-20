import SwiftUI
import SwiftData

struct HabitsPage: View {
    @Query(sort: \Habit.created) private var habits: [Habit]
    @Environment(UI.self) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Habits").rise()
            Heading(muted: "Small things, every day.", strong: summary).padding(.top, 20).rise(0.05)

            if habits.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    Text("No habits yet.").font(.wave(20, .medium)).tracking(-0.5)
                    Text("Pick something small you want to do every day. The grid fills in as you go.")
                        .foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(4)
                    PrimaryButton(title: "New habit", icon: "plus", large: true) { ui.open(.newHabit) }
                }
                .padding(32).frame(maxWidth: 520, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
                .padding(.top, 48).rise(0.1)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 12) {
                    ForEach(Array(habits.enumerated()), id: \.element.persistentModelID) { i, habit in
                        HabitCard(habit: habit).rise(0.1 + Double(i) * 0.1)
                    }
                }
                .padding(.top, 56)
            }
        }
    }

    private var summary: String {
        let done = habits.filter { $0.isDone(.now) }.count
        return habits.isEmpty ? "Nothing tracked yet." : "\(done) of \(habits.count) done today."
    }
}

/// The service card: `rounded-3xl p-1.5` frame with two paper blocks. Done today flips it to ink + violet.
struct HabitCard: View {
    let habit: Habit
    @Environment(UI.self) private var ui
    @Environment(\.modelContext) private var context

    var body: some View {
        let done = habit.isDone(.now)
        let fg = done ? Theme.paper : Theme.ink
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text(habit.name).font(.wave(20, .medium)).tracking(-0.5).lineLimit(1)
                Spacer(minLength: 8)
                MenuButton(onDark: done, items: [
                    ("Edit", false, { ui.open(.editHabit(habit)) }),
                    ("Delete", true, { context.delete(habit) }),
                ])
                Button { habit.toggle(.now) } label: {
                    Icon(habit.icon, size: 24, color: done ? Theme.violet : habit.tint, weight: .fill)
                        .frame(width: 44, height: 44)
                        .background(done ? Theme.paper : habit.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .cardBlock(done ? Theme.violet : Theme.paper)

            VStack(alignment: .leading, spacing: 20) {
                Text(habit.streak == 0 ? "No streak yet. Today is a good day to start."
                     : "\(habit.streak) day streak. Keep the row going.")
                    .foregroundStyle(fg.opacity(done ? 0.8 : 0.6)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                HabitGrid(habit: habit, onDark: done)
                HStack(spacing: 8) {
                    Chip(text: done ? "Done today" : "Open", onDark: done)
                    Chip(text: "\(habit.days.count) days total", onDark: done)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBlock(done ? Theme.violet : Theme.paper)
        }
        .foregroundStyle(fg)
        .cardFrame(dark: done)
        .animation(.easeOut(duration: 0.25), value: done)
    }
}

struct HabitGrid: View {
    let habit: Habit
    var onDark = false
    private let weeks = 18

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekEnd = cal.date(byAdding: .day, value: 7 - cal.component(.weekday, from: today), to: today)!
        let start = cal.date(byAdding: .day, value: 1 - weeks * 7, to: weekEnd)!
        HStack(spacing: 3) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { d in
                        let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(day > today ? Color.clear
                                  : habit.isDone(day) ? (onDark ? Theme.paper : habit.tint)
                                  : (onDark ? Theme.paper.opacity(0.18) : Theme.ink.opacity(0.08)))
                            .frame(width: 12, height: 12)
                            .onTapGesture { if day <= today { habit.toggle(day) } }
                    }
                }
            }
        }
    }
}

struct HabitEditor: View {
    let habit: Habit?
    @Environment(\.modelContext) private var context
    @Environment(UI.self) private var ui
    @State private var name = ""
    @State private var icon = Habit.icons[0]
    @State private var color = Habit.palette[0].0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelTitle(text: habit == nil ? "New habit" : "Edit habit")
            TextField("Name", text: $name).waveField()
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 8), spacing: 6) {
                ForEach(Habit.icons, id: \.self) { i in
                    Icon(i, size: 20, color: i == icon ? Theme.paper : Theme.ink, weight: .fill)
                        .frame(width: 36, height: 36)
                        .background(i == icon ? Theme.ink : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { icon = i }
                }
            }
            HStack(spacing: 8) {
                ForEach(Habit.palette, id: \.0) { key, tint in
                    Circle().fill(tint).frame(width: 24, height: 24)
                        .overlay { if key == color { Circle().stroke(Theme.ink, lineWidth: 2).padding(-3) } }
                        .onTapGesture { color = key }
                }
            }
            PanelButtons(primary: "Save", disabled: name.isEmpty, action: save)
        }
        .panel(width: 460)
        .onAppear { if let habit { name = habit.name; icon = habit.icon; color = habit.color } }
    }

    private func save() {
        if let habit { habit.name = name; habit.icon = icon; habit.color = color }
        else { context.insert(Habit(name: name, icon: icon, color: color)) }
        ui.close()
    }
}
