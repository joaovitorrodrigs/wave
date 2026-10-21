import WidgetKit
import SwiftUI
import AppIntents
import PhosphorSwift

/// Habits on the desktop: the app's habit cards, one draw call per grid, tap the icon to check today.
/// Data arrives as `habits.json` written by the app into this extension's container; toggles go back as `toggles.json`.
@main struct WaveWidgets: WidgetBundle {
    init() {
        if let url = Bundle.main.url(forResource: "InstrumentSans", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    var body: some Widget { HabitsWidget() }
}

struct HabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "habits", provider: HabitsProvider()) { entry in
            HabitsView(entry: entry)
                .containerBackground(for: .widget) { WidgetTheme.canvas }
        }
        .configurationDisplayName("Habits")
        .description("Your habits and their grids. Tap an icon to check today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

enum Bridge {
    static var dir: URL { URL.applicationSupportDirectory.appending(path: "Wave") }
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    static func load() -> [HabitSnapshot] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)   // so the app finds the container
        guard let data = try? Data(contentsOf: dir.appending(path: "habits.json")) else { return [] }
        return (try? decoder.decode([HabitSnapshot].self, from: data)) ?? []
    }

    static func save(_ habits: [HabitSnapshot]) {
        if let data = try? encoder.encode(habits) { try? data.write(to: dir.appending(path: "habits.json"), options: .atomic) }
    }

    static func queue(_ toggle: HabitToggle) {
        let url = dir.appending(path: "toggles.json")
        var list = (try? Data(contentsOf: url)).flatMap { try? decoder.decode([HabitToggle].self, from: $0) } ?? []
        list.append(toggle)
        if let data = try? encoder.encode(list) { try? data.write(to: url, options: .atomic) }
    }
}

struct HabitsEntry: TimelineEntry {
    let date: Date
    let habits: [HabitSnapshot]
}

struct HabitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry { HabitsEntry(date: .now, habits: []) }
    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) { completion(HabitsEntry(date: .now, habits: Bridge.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        completion(Timeline(entries: [HabitsEntry(date: .now, habits: Bridge.load())], policy: .after(midnight)))
    }
}

struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Habit"
    @Parameter(title: "Habit") var id: Double
    init() {}
    init(id: Double) { self.id = id }
    func perform() async throws -> some IntentResult {
        var habits = Bridge.load()
        let day = Calendar.current.startOfDay(for: .now)
        if let i = habits.firstIndex(where: { $0.id == id }) {
            if let j = habits[i].days.firstIndex(of: day) { habits[i].days.remove(at: j) } else { habits[i].days.append(day) }
            Bridge.save(habits)
            Bridge.queue(HabitToggle(id: id, day: day))
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "habits")
        return .result()
    }
}

/// The app's tokens, picked by scheme since dynamic NSColors do not resolve inside widgets.
struct WidgetTheme {
    static let inkLight = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let darkCard = Color(white: 0x12 / 255)
    static let lightCard = Color(white: 0xF2 / 255)
    static let canvas = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white })
    static let palette: [String: Color] = ["red": .red, "orange": .orange, "yellow": .yellow, "green": .green, "mint": .mint,
                                           "teal": .teal, "blue": .blue, "indigo": .indigo, "purple": .purple, "pink": .pink]
    let dark: Bool
    var ink: Color { dark ? .white : Self.inkLight }
    var paper: Color { dark ? .black : .white }
    var surface: Color { ink.opacity(dark ? 0.08 : 0.04) }
    var card: Color { dark ? Self.lightCard : Self.darkCard }
}

struct HabitsView: View {
    let entry: HabitsEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = WidgetTheme(dark: scheme == .dark)
        let shown: [HabitSnapshot] = Array(entry.habits.prefix(family == .systemSmall ? 1 : family == .systemMedium ? 2 : 4))
        Group {
            if shown.isEmpty {
                Text("Open Wave once to sync your habits.").font(.custom("Instrument Sans", size: 13))
                    .foregroundStyle(theme.ink.opacity(0.6)).multilineTextAlignment(.center).padding()
            } else if family == .systemLarge {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(shown) { HabitCardView(habit: $0, theme: theme) }
                }
            } else {
                HStack(spacing: 8) { ForEach(shown) { HabitCardView(habit: $0, theme: theme) } }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The app's habit card: frame with two blocks, inverted to ink when today is done.
struct HabitCardView: View {
    let habit: HabitSnapshot
    let theme: WidgetTheme

    var body: some View {
        let done = habit.isDone(.now)
        let tint = WidgetTheme.palette[habit.color] ?? .blue
        let fg = done ? theme.paper : theme.ink
        let block = done ? theme.card : theme.paper
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(habit.name).font(.custom("Instrument Sans", size: 13).weight(.medium)).lineLimit(1).foregroundStyle(fg)
                Spacer(minLength: 4)
                Button(intent: ToggleHabitIntent(id: habit.id)) {
                    PhIcon(habit.icon, size: 14, color: done ? theme.paper : tint)
                        .frame(width: 28, height: 28)
                        .background(done ? tint : tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(block, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text(habit.streak == 0 ? "No streak yet" : "\(habit.streak) day streak")
                    .font(.custom("Instrument Sans", size: 11)).foregroundStyle(fg.opacity(0.6))
                GeometryReader { g in
                    HabitGridCanvas(days: Set(habit.days), tint: tint, empty: fg.opacity(0.1), width: g.size.width)
                }
                .frame(height: 7 * 9 - 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(block, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(4)
        .background(done ? theme.ink : theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PhIcon: View {
    let name: String
    let size: CGFloat
    let color: Color
    static let legacy = ["figure.run": "person-simple-run", "dumbbell": "barbell", "fork.knife": "fork-knife", "bed.double": "bed",
                         "sun.max": "sun", "music.note": "music-note", "dollarsign": "currency-dollar", "laptopcomputer": "laptop"]
    init(_ name: String, size: CGFloat, color: Color) { self.name = name; self.size = size; self.color = color }
    var body: some View {
        (Ph(rawValue: name) ?? Ph(rawValue: Self.legacy[name] ?? "") ?? .circle).fill.color(color).frame(width: size, height: size)
    }
}

struct HabitGridCanvas: View {
    let days: Set<Date>
    let tint: Color
    let empty: Color
    let width: CGFloat
    private let cell: CGFloat = 7
    private let gap: CGFloat = 2

    var body: some View {
        let pitch = cell + gap
        let weeks = max(1, Int((width + gap) / pitch))
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekEnd = cal.date(byAdding: .day, value: 7 - cal.component(.weekday, from: today), to: today)!
        let start = cal.date(byAdding: .day, value: 1 - weeks * 7, to: weekEnd)!
        Canvas { context, _ in
            for w in 0..<weeks {
                for d in 0..<7 {
                    let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                    if day > today { continue }
                    let rect = CGRect(x: CGFloat(w) * pitch, y: CGFloat(d) * pitch, width: cell, height: cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(days.contains(day) ? tint : empty))
                }
            }
        }
    }
}
