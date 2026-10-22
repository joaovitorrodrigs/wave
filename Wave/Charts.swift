import SwiftUI

/// Twelve months of income and spend as paired bars, drawn in one Canvas.
struct BarPairsChart: View {
    let data: [(label: String, income: Decimal, spent: Decimal)]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink: Color = scheme == .dark ? .white : Theme.inkStatic
        Canvas { context, size in
            let maxValue = data.flatMap { [$0.income, $0.spent] }.map { Double(truncating: $0 as NSNumber) }.max() ?? 1
            let labelHeight: CGFloat = 18
            let plotHeight = size.height - labelHeight
            let slot = size.width / CGFloat(max(data.count, 1))
            let barWidth = min(14, (slot - 10) / 2)
            for (i, d) in data.enumerated() {
                let x = CGFloat(i) * slot + slot / 2
                for (j, value, color) in [(0, d.income, Theme.brand), (1, d.spent, ink)] {
                    let h = maxValue > 0 ? CGFloat(Double(truncating: value as NSNumber) / maxValue) * (plotHeight - 4) : 0
                    let bx = x - barWidth - 2 + CGFloat(j) * (barWidth + 4)
                    let rect = CGRect(x: bx, y: plotHeight - h, width: barWidth, height: max(h, 2))
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(value == 0 ? ink.opacity(0.1) : color))
                }
                context.draw(Text(d.label).font(.custom("Instrument Sans", size: 11)).foregroundStyle(ink.opacity(0.5)),
                             at: CGPoint(x: x, y: size.height - 6))
            }
        }
    }
}

/// A value over time with a soft violet fill under it.
struct LineChart: View {
    let points: [(date: Date, value: Decimal)]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink: Color = scheme == .dark ? .white : Theme.inkStatic
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let values = points.map { Double(truncating: $0.value as NSNumber) }
            let lo = values.min()!, hi = values.max()!
            let span = max(hi - lo, 1)
            let inset: CGFloat = 8
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: inset + CGFloat(i) / CGFloat(points.count - 1) * (size.width - 2 * inset),
                        y: inset + (1 - CGFloat((values[i] - lo) / span)) * (size.height - 2 * inset))
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<points.count { line.addLine(to: point(i)) }
            var area = line
            area.addLine(to: CGPoint(x: point(points.count - 1).x, y: size.height))
            area.addLine(to: CGPoint(x: point(0).x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [Theme.violet.opacity(0.25), Theme.violet.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(Theme.violet), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            let last = point(points.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)), with: .color(Theme.violet))
            context.fill(Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)), with: .color(ink == .white ? .black : .white))
        }
    }
}

/// Horizontal bar as a share of a maximum, with an optional budget mark.
struct ShareBar: View {
    let share: Double
    var over = false
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.08))
                Capsule().fill(over ? Theme.danger : Theme.ink).frame(width: max(0, min(1, share)) * g.size.width)
            }
        }
        .frame(height: 8)
    }
}
