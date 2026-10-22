import SwiftUI

/// Toggle as a pill: ink when on, paper knob.
struct Switch: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { isOn.toggle() } } label: {
            HStack {
                Text(title).font(.wave(16, .medium))
                Spacer()
                Capsule().fill(isOn ? Theme.ink : Theme.ink.opacity(0.12))
                    .frame(width: 44, height: 26)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(Theme.paper).padding(3).shadow(color: Theme.shadow.opacity(0.25), radius: 2, y: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Field-shaped trigger: label left, value right, chevron. Used by Select and DateField.
struct FieldButton: View {
    let title: String
    let value: String
    let open: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(Theme.ink.opacity(0.5))
                Spacer()
                Text(value).font(.wave(16, .medium)).lineLimit(1)
                Icon("caret-down", size: 14, color: Theme.ink.opacity(0.6))
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct OptionRow: View {
    let text: String
    var selected = false
    var destructive = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack {
                Text(text).font(.wave(16, selected ? .medium : .regular))
                Spacer()
                if selected { Icon("check", size: 14) }
            }
            .foregroundStyle(selected ? Theme.paper : destructive ? Theme.danger : Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.ink : Theme.ink.opacity(hover ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Dropdown that opens as an accordion under the field, like the FAQ rows.
struct Select<T: Hashable>: View {
    let title: String
    @Binding var value: T
    let options: [(T, String)]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldButton(title: title, value: options.first { $0.0 == value }?.1 ?? "", open: open) {
                withAnimation(.easeOut(duration: 0.2)) { open.toggle() }
            }
            if open {
                VStack(spacing: 2) {
                    ForEach(options, id: \.0) { option in
                        OptionRow(text: option.1, selected: option.0 == value) {
                            value = option.0
                            withAnimation(.easeOut(duration: 0.2)) { open = false }
                        }
                    }
                }
                .padding(6)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
                .padding(6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Date and time picker: the month grid plus hour and minute steppers, as an accordion.
struct DateField: View {
    let title: String
    @Binding var date: Date
    @State private var open = false
    @State private var month = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldButton(title: title, value: date.formatted(date: .abbreviated, time: .shortened), open: open) {
                withAnimation(.easeOut(duration: 0.2)) { open.toggle() }
            }
            if open {
                VStack(spacing: 20) {
                    MonthGrid(month: $month, selected: day, eventDays: [])
                    TimeRow(date: $date)
                }
                .padding(20)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
                .padding(6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear { month = date }
    }

    private var day: Binding<Date> {
        Binding(get: { date }, set: { newDay in
            let cal = Calendar.current
            let time = cal.dateComponents([.hour, .minute], from: date)
            date = cal.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: newDay) ?? newDay
        })
    }

}

/// A set date, shown as text with a "Change" chip; the month grid only opens on request.
struct DateSummary: View {
    let date: Date
    @Binding var editing: Bool
    var body: some View {
        HStack {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.wave(16, .medium))
            Spacer()
            Button { withAnimation(.easeOut(duration: 0.2)) { editing.toggle() } } label: { Chip(text: editing ? "Done" : "Change", selected: editing) }
                .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
    }
}

/// Hour and minute steppers plus the three usual times.
struct TimeRow: View {
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TimeStepper(value: hour, range: 0...23, step: 1)
                Text(":").font(.wave(20, .medium))
                TimeStepper(value: minute, range: 0...55, step: 5)
            }
            HStack(spacing: 8) {
                ForEach([9, 12, 18], id: \.self) { h in
                    Button { set(hour: h, minute: 0) } label: { Chip(text: String(format: "%02d:00", h), selected: hour.wrappedValue == h && minute.wrappedValue == 0) }
                        .buttonStyle(PressStyle())
                }
            }
        }
    }

    private var hour: Binding<Int> {
        Binding(get: { Calendar.current.component(.hour, from: date) }, set: { set(hour: $0, minute: minute.wrappedValue) })
    }

    private var minute: Binding<Int> {
        Binding(get: { Calendar.current.component(.minute, from: date) / 5 * 5 }, set: { set(hour: hour.wrappedValue, minute: $0) })
    }

    private func set(hour h: Int, minute m: Int) {
        date = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
    }
}

struct TimeStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var body: some View {
        HStack(spacing: 4) {
            stepButton("minus") { value = value - step < range.lowerBound ? range.upperBound : value - step }
            Text(String(format: "%02d", value)).font(.wave(18, .medium)).monospacedDigit().frame(width: 34)
            stepButton("plus") { value = value + step > range.upperBound ? range.lowerBound : value + step }
        }
        .padding(4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 13, color: Theme.ink)
                .frame(width: 28, height: 28).background(Theme.paper, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(PressStyle())
    }
}

/// Scrolls only when the content is taller than `max`; otherwise it is exactly as tall as its content.
struct FitScroll<Content: View>: View {
    let max: CGFloat
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0
    var body: some View {
        ScrollView {
            content.background(GeometryReader { g in
                Color.clear.onAppear { height = g.size.height }.onChange(of: g.size.height) { _, new in height = new }
            })
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .frame(height: height == 0 ? nil : min(height, max))
    }
}

/// Small rotating arc, instead of ProgressView.
struct Spinner: View {
    var onDark = false
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Circle().trim(from: 0.2, to: 1)
            .stroke(onDark ? Theme.paper : Theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { if !reduce { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } } }
    }
}

/// `⋯` button. The menu itself is drawn by ModalHost, above every row, and closes on a click anywhere else.
struct MenuButton: View {
    var onDark = false
    var color: Color? = nil                   // icon colour override, for violet rows
    let items: [(String, Bool, () -> Void)]   // title, destructive, action
    @Environment(UI.self) private var ui
    @State private var frame = CGRect.zero

    var body: some View {
        Button {
            if ui.menu != nil { ui.closeMenu() } else { ui.openMenu(items, at: frame) }
        } label: {
            Icon("dots-three", size: 18, color: color ?? (onDark ? Theme.paper : Theme.ink))
                .frame(width: 32, height: 32)
                .background((color ?? (onDark ? Theme.paper : Theme.ink)).opacity(onDark ? 0.15 : 0.05), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { frame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, new in frame = new }
        })
    }
}
