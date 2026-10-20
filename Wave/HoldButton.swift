import SwiftUI

/// Port of React Bits' HoldButton in Wave's tokens: ink body, `#DC2F3A` fill that sweeps in with a wavy
/// crest while you hold (2 s), label crossfades to "Deleted", 0.97 press scale, fill-colored glow, pulse on
/// completion. Letting go early eases the fill back out; a short tap does nothing. Keyboard hold is not ported.
struct HoldButton: View {
    var title = "Hold to delete"
    var doneTitle = "Deleted"
    var icon: String? = "trash"
    var holdTime: Double = 2
    var compact = false
    let action: () -> Void

    private enum Phase { case idle, holding, done }
    @State private var phase: Phase = .idle
    @State private var progress: CGFloat = 0
    @State private var start = Date.distantPast
    @State private var pulse = false
    @State private var timer: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var radius: CGFloat { 14 }
    private var height: CGFloat { compact ? 36 : 44 }

    @State private var size = CGSize.zero

    var body: some View {
        labels(color: Theme.paper)
            .frame(height: height)
            .frame(minWidth: compact ? 150 : 180)
            .background(Theme.ink)
            .overlay {
                ZStack {
                    Theme.danger
                    labels(color: .white)
                }
                .mask(Crest(progress: progress, amplitude: reduce ? 0 : 3, cycles: holdTime / 1.1))
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.danger.opacity(pulse ? 0 : 0.55), lineWidth: pulse ? 14 : 1)
                    .padding(pulse ? -7 : 0)
                    .opacity(phase == .done ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .shadow(color: Theme.danger.opacity(phase == .idle ? 0 : 0.7), radius: 13, y: 10)
            .scaleEffect(phase == .holding && !reduce ? 0.97 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.16), value: phase)
            .contentShape(Rectangle())
            .background(GeometryReader { g in
                Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, new in size = new }
            })
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if phase == .idle { begin() }
                        let pad: CGFloat = 10
                        let inside = value.location.x > -pad && value.location.x < size.width + pad
                            && value.location.y > -pad && value.location.y < size.height + pad
                        if !inside { release() }
                    }
                    .onEnded { _ in release() }
            )
    }

    private func labels(color: Color) -> some View {
        ZStack {
            label(icon, title).opacity(phase == .done ? 0 : 1).blur(radius: phase == .done ? 2 : 0)
            label("check", doneTitle).opacity(phase == .done ? 1 : 0).blur(radius: phase == .done ? 0 : 2)
        }
        .foregroundStyle(color)
        .animation(.easeInOut(duration: 0.2), value: phase)
        .padding(.horizontal, compact ? 16 : 22)
    }

    private func label(_ icon: String?, _ text: String) -> some View {
        HStack(spacing: 8) {
            if let icon { IconTinted(name: icon, size: compact ? 14 : 16) }
            Text(text).font(.wave(compact ? 13 : 15, .medium)).lineLimit(1)
        }
    }

    private func begin() {
        phase = .holding
        start = .now
        withAnimation(.linear(duration: holdTime)) { progress = 1 }
        timer?.cancel()
        timer = Task {
            try? await Task.sleep(for: .seconds(holdTime + 0.1))
            guard !Task.isCancelled, phase == .holding, Date.now.timeIntervalSince(start) >= holdTime - 0.05 else { return }
            complete()
        }
    }

    private func release() {
        guard phase == .holding else { return }
        timer?.cancel()
        phase = .idle
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) { progress = 0 }
    }

    private func complete() {
        phase = .done
        pulse = false
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.6)) { pulse = true }
        action()
        timer = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            phase = .idle
            pulse = false
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) { progress = 0 }
        }
    }
}

/// Phosphor glyph as a mask over the current foreground style, so both label layers tint themselves.
private struct IconTinted: View {
    let name: String
    let size: CGFloat
    var body: some View {
        Rectangle().fill(.primary).frame(width: size, height: size)
            .mask { Icon(name, size: size, color: .black) }
    }
}

/// The fill: everything left of a vertical crest that travels with progress and ripples as it goes.
private struct Crest: Shape {
    var progress: CGFloat
    var amplitude: CGFloat
    var cycles: Double

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let wave = amplitude * 2
        let edge = -wave + progress * (rect.width + wave)
        path.move(to: CGPoint(x: 0, y: 0))
        var y: CGFloat = 0
        while y <= rect.height {
            let x = edge + amplitude * sin((y / 33 + Double(progress) * cycles) * 2 * .pi)
            path.addLine(to: CGPoint(x: x, y: y))
            y += 2
        }
        path.addLine(to: CGPoint(x: edge + amplitude, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
