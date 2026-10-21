import WidgetKit
import SwiftUI

// MARK: - Weather

struct WeatherEntry: TimelineEntry {
    let date: Date
    let forecast: Forecast?
    let place: String
    var appearance: WidgetAppearance = .auto
}

struct WeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry { WeatherEntry(date: .now, forecast: nil, place: "") }
    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) { Task { completion(await load(.current)) } }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        Task { completion(Timeline(entries: [await load(.current)], policy: .after(Date.now.addingTimeInterval(1800)))) }
    }
    private func load(_ appearance: WidgetAppearance) async -> WeatherEntry {
        guard let data = try? Data(contentsOf: Bridge.dir.appending(path: "location.json")),
              let location = try? Bridge.decoder.decode(LocationSnapshot.self, from: data) else { return WeatherEntry(date: .now, forecast: nil, place: "", appearance: appearance) }
        let forecast = try? await Forecast.fetch(latitude: location.latitude, longitude: location.longitude)
        return WeatherEntry(date: .now, forecast: forecast, place: location.place, appearance: appearance)
    }
}

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "wave.weather", provider: WeatherProvider()) { entry in
            WeatherView(entry: entry).containerBackground(for: .widget) { WidgetCanvas(appearance: entry.appearance) }
        }
        .configurationDisplayName("Weather")
        .description("Now, high and low, and the next hours.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WeatherView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = WidgetTheme.resolve(entry.appearance, scheme: scheme)
        if let f = entry.forecast {
            let now = WeatherCodes.describe(f.code, isDay: f.isDay)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text("\(Int(f.temperature.rounded()))°").font(.custom("Instrument Sans", size: 40).weight(.medium)).foregroundStyle(theme.ink)
                        Spacer(minLength: 0)
                        PhIcon(now.icon, size: 28, color: theme.ink)
                    }
                    Spacer(minLength: 0)
                    Text(entry.place.isEmpty ? now.label : entry.place).font(.custom("Instrument Sans", size: 13).weight(.medium)).foregroundStyle(theme.ink).lineLimit(1)
                    Text("\(now.label) · H \(Int(f.high.rounded()))° L \(Int(f.low.rounded()))°").font(.custom("Instrument Sans", size: 11)).foregroundStyle(theme.ink.opacity(0.6)).lineLimit(1)
                }
                if family == .systemMedium {
                    HStack(spacing: 0) {
                        ForEach(f.hours) { h in
                            VStack(spacing: 6) {
                                Text(h.time.formatted(.dateTime.hour())).font(.custom("Instrument Sans", size: 10)).foregroundStyle(theme.ink.opacity(0.5))
                                PhIcon(WeatherCodes.describe(h.code, isDay: true).icon, size: 14, color: theme.ink.opacity(0.7))
                                Text("\(Int(h.temperature.rounded()))°").font(.custom("Instrument Sans", size: 12).weight(.medium)).foregroundStyle(theme.ink)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        } else {
            Text("Open Wave once so the widget knows where you are.").font(.custom("Instrument Sans", size: 12))
                .foregroundStyle(theme.ink.opacity(0.6)).multilineTextAlignment(.center)
        }
    }
}

// MARK: - Calendar

struct CalendarEntry: TimelineEntry {
    let date: Date
    let events: [EventSnapshot]
    var appearance: WidgetAppearance = .auto
}

struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry { CalendarEntry(date: .now, events: []) }
    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) { completion(load(.current)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        completion(Timeline(entries: [load(.current)], policy: .after(midnight)))
    }
    private func load(_ appearance: WidgetAppearance) -> CalendarEntry {
        let data = try? Data(contentsOf: Bridge.dir.appending(path: "events.json"))
        return CalendarEntry(date: .now, events: data.flatMap { try? Bridge.decoder.decode([EventSnapshot].self, from: $0) } ?? [], appearance: appearance)
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "wave.calendar", provider: CalendarProvider()) { entry in
            CalendarView(entry: entry).containerBackground(for: .widget) { WidgetCanvas(appearance: entry.appearance) }
        }
        .configurationDisplayName("Calendar")
        .description("This month, with today's and tomorrow's events.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CalendarView: View {
    let entry: CalendarEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    private let violet = Color(red: 0x74 / 255, green: 0x30 / 255, blue: 0xF7 / 255)

    var body: some View {
        let theme = WidgetTheme.resolve(entry.appearance, scheme: scheme)
        HStack(spacing: 16) {
            month(theme)
            if family == .systemMedium { agenda(theme) }
        }
    }

    /// Apple's month layout in Wave's violet: light digits, past days dimmed, weekends dimmer, and the
    /// neighbouring months' days kept in the grid instead of blanks.
    private func month(_ theme: WidgetTheme) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let first = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let offset = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: today)!.count
        let rows = Int(ceil(Double(offset + count) / 7))
        let gridStart = cal.date(byAdding: .day, value: -offset, to: first)!
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let weekdays = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return VStack(alignment: .leading, spacing: 6) {
            Text(today.formatted(.dateTime.month(.wide)).uppercased()).font(.custom("Instrument Sans", size: 10).weight(.semibold)).tracking(0.3).foregroundStyle(theme.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 5) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { i, symbol in
                    Text(symbol).id("w\(i)").font(.custom("Instrument Sans", size: 9).weight(.medium)).foregroundStyle(theme.ink.opacity(0.45))
                }
                ForEach((0..<(rows * 7)).map { "d\($0)" }, id: \.self) { key in
                    let i = Int(key.dropFirst())!
                    let day = cal.date(byAdding: .day, value: i, to: gridStart)!
                    let inMonth = cal.isDate(day, equalTo: today, toGranularity: .month)
                    let isToday = cal.isDate(day, inSameDayAs: today)
                    let weekend = cal.isDateInWeekend(day)
                    Text("\(cal.component(.day, from: day))").font(.custom("Instrument Sans", size: 10).weight(isToday ? .medium : .regular))
                        .foregroundStyle(isToday ? Color.white : theme.ink.opacity(!inMonth ? 0.25 : day < today ? 0.45 : weekend ? 0.6 : 1))
                        .frame(width: 18, height: 18)
                        .background(isToday ? violet : .clear, in: Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func agenda(_ theme: WidgetTheme) -> some View {
        let cal = Calendar.current
        let todayEvents = entry.events.filter { cal.isDateInToday($0.start) }.prefix(3)
        let tomorrowEvents = entry.events.filter { cal.isDateInTomorrow($0.start) }.prefix(2)
        return VStack(alignment: .leading, spacing: 6) {
            section("Today", Array(todayEvents), theme)
            section("Tomorrow", Array(tomorrowEvents), theme)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func section(_ title: String, _ events: [EventSnapshot], _ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.custom("Instrument Sans", size: 10).weight(.semibold)).foregroundStyle(theme.ink.opacity(0.5))
            if events.isEmpty {
                Text("Nothing").font(.custom("Instrument Sans", size: 11)).foregroundStyle(theme.ink.opacity(0.4))
            }
            ForEach(events) { e in
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: e.color)).frame(width: 6, height: 6)
                    Text(e.allDay ? "All day" : e.start.formatted(date: .omitted, time: .shortened)).font(.custom("Instrument Sans", size: 10)).foregroundStyle(theme.ink.opacity(0.5)).monospacedDigit()
                    Text(e.title).font(.custom("Instrument Sans", size: 11).weight(.medium)).foregroundStyle(theme.ink).lineLimit(1)
                }
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0x7430F7
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
