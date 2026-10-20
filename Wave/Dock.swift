import SwiftUI

/// Port of skecher-ui's Dock (CoDesign-Spa27/skecher-ui/dock) in Wave's identity: ink surface, violet for the
/// active page, magnification by mouse distance, label on hover. No hover highlight: motion is the feedback. Same numbers as the original where they fit: base 44, max 72, influence 140,
/// radius 16, item radius 14, tap scale 0.88.
struct DockItem: Identifiable {
    let id: String
    let label: String
    let icon: String
    var active = false
    let action: () -> Void
}

struct Dock: View {
    let items: [DockItem]
    private let base: CGFloat = 44
    private let maxSize: CGFloat = 72
    private let influence: CGFloat = 140
    @State private var mouseX: CGFloat?
    @State private var frames: [String: CGRect] = [:]
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(items) { item in
                if item.id.hasPrefix("|") {
                    Rectangle().fill(Theme.paper.opacity(0.15)).frame(width: 1, height: 24).padding(.horizontal, 2).padding(.bottom, 10)
                } else {
                    let size = size(for: item)
                    Button(action: item.action) {
                        Icon(item.icon, size: size * 0.5, color: Theme.paper, weight: .fill)
                            .frame(width: size, height: size)
                            .background(item.active ? Theme.violet : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(DockPress())
                    .onHover { if $0 { hovered = item.id } }
                    // The layout slot keeps the dock's height: only the width flows, the icon overflows upward.
                    .frame(width: size, height: base, alignment: .bottom)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: DockFrames.self, value: [item.id: g.frame(in: .named("dock"))])
                    })
                    .overlay(alignment: .top) {
                        if hovered == item.id {
                            Text(item.label).font(.wave(13, .medium)).foregroundStyle(Theme.ink)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                                .shadow(color: Theme.shadow.opacity(0.2), radius: 8, y: 6)
                                .fixedSize()
                                .offset(y: -42)
                                .allowsHitTesting(false)
                                .transition(.opacity.combined(with: .offset(y: 4)))
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        .shadow(color: Theme.shadow.opacity(0.35), radius: 20, y: 14)
        .coordinateSpace(name: "dock")
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): mouseX = point.x
            case .ended: mouseX = nil; hovered = nil
            }
        }
        .onPreferenceChange(DockFrames.self) { frames = $0 }
        .animation(reduce ? nil : .spring(duration: 0.28, bounce: 0.25), value: mouseX)
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    private func size(for item: DockItem) -> CGFloat {
        guard !reduce, let mouseX, let frame = frames[item.id] else { return base }
        let proximity = 1 - min(abs(mouseX - frame.midX) / influence, 1)
        return base + (maxSize - base) * proximity
    }

}

struct DockFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// `whileTap={{ scale: 0.88 }}`
struct DockPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
    }
}

extension Page {
    var icon: String {
        switch self {
        case .home: "house"
        case .today: "sun"
        case .calendar: "calendar-blank"
        case .habits: "check-square"
        case .notes: "note"
        case .finances: "credit-card"
        case .clients: "users"
        case .review: "chart-line-up"
        }
    }
}
