import SwiftUI
import SwiftData

struct HabitsView: View {
    @Query(sort: \Habit.created) private var habits: [Habit]
    @Environment(\.modelContext) private var context
    @State private var editing: Habit?
    @State private var adding = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(habits) { habit in
                    HabitCard(habit: habit).contextMenu {
                        Button("Edit") { editing = habit }
                        Button("Delete", role: .destructive) { context.delete(habit) }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Habits")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { HabitEditor(habit: nil) }
        .sheet(item: $editing) { HabitEditor(habit: $0) }
        .overlay {
            if habits.isEmpty {
                ContentUnavailableView("No habits yet", systemImage: "checkmark.square", description: Text("Press + to add one."))
            }
        }
    }
}

struct HabitCard: View {
    let habit: Habit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: habit.icon)
                    .font(.title3).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(habit.tint, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text(habit.name).font(.headline)
                    Label("\(habit.streak) day streak", systemImage: "flame").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { habit.toggle(.now) } label: {
                    Image(systemName: habit.isDone(.now) ? "checkmark.circle.fill" : "circle").font(.title).foregroundStyle(habit.tint)
                }
                .buttonStyle(.plain)
            }
            HabitGrid(habit: habit)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct HabitGrid: View {
    let habit: Habit
    private let weeks = 26

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
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day > today ? Color.clear : habit.isDone(day) ? habit.tint : Color.primary.opacity(0.08))
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
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = Habit.icons[0]
    @State private var color = Habit.palette[0].0

    var body: some View {
        Form {
            TextField("Name", text: $name)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8)) {
                ForEach(Habit.icons, id: \.self) { i in
                    Image(systemName: i).frame(width: 32, height: 32)
                        .background(i == icon ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .onTapGesture { icon = i }
                }
            }
            HStack {
                ForEach(Habit.palette, id: \.0) { key, tint in
                    Circle().fill(tint).frame(width: 22, height: 22)
                        .overlay { if key == color { Circle().stroke(.primary, lineWidth: 2) } }
                        .onTapGesture { color = key }
                }
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(name.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onAppear { if let habit { name = habit.name; icon = habit.icon; color = habit.color } }
    }

    private func save() {
        if let habit { habit.name = name; habit.icon = icon; habit.color = color }
        else { context.insert(Habit(name: name, icon: icon, color: color)) }
        dismiss()
    }
}
