import SwiftUI
import AppKit
import PhosphorSwift

/// Phosphor icon by kebab-case name. Like the site: `bold` for arrows, carets and controls, `fill` for feature icons.
/// Old SF Symbol names stored in habits still resolve.
struct Icon: View {
    let name: String
    var size: CGFloat = 20
    var color: Color = Theme.ink
    var weight: Ph.IconWeight = .bold

    init(_ name: String, size: CGFloat = 20, color: Color = Theme.ink, weight: Ph.IconWeight = .bold) {
        self.name = name; self.size = size; self.color = color; self.weight = weight
    }

    static let legacy: [String: String] = [
        "figure.run": "person-simple-run", "dumbbell": "barbell", "fork.knife": "fork-knife", "bed.double": "bed",
        "sun.max": "sun", "music.note": "music-note", "dollarsign": "currency-dollar", "laptopcomputer": "laptop",
    ]

    var body: some View {
        (Ph(rawValue: name) ?? Ph(rawValue: Icon.legacy[name] ?? "") ?? .circle)
            .weight(weight).color(color)
            .frame(width: size, height: size)
    }
}

/// Tokens and primitives from wavestudio.pro (`src/index.css` and the Home components).
enum Theme {
    static let ink = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let paper = Color.white
    static let black = Color.black
    static let brand = Color(red: 0, green: 0xC0 / 255, blue: 0x47 / 255)
    static let violet = Color(red: 0x74 / 255, green: 0x30 / 255, blue: 0xF7 / 255)
    static let surface = ink.opacity(0.04)     // bg-ink/[0.04]
    static let chip = ink.opacity(0.05)        // bg-ink/[0.05]
    static let darkCard = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)
    static let radiusButton: CGFloat = 16      // --radius-btn
    static let radiusBlock: CGFloat = 18       // inner blocks of nested cards
    static let radiusCard: CGFloat = 24        // rounded-3xl
    static let radiusBig: CGFloat = 32         // rounded-4xl
    static let radiusSection: CGFloat = 40     // rounded-[40px]
    static let curve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)

    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "InstrumentSans", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Sparse white specks tiled over black sections at 50%, the site's `.grain`.
    static let grain: NSImage = {
        let n = 160
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let v = Int.random(in: 0...255)
            px[i * 4] = 255; px[i * 4 + 1] = 255; px[i * 4 + 2] = 255
            px[i * 4 + 3] = UInt8(max(0, v - 200) * 255 / 55)
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: n, height: n))
    }()
}

extension Font {
    static func wave(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Instrument Sans", size: size).weight(weight)
    }
}

/// `active:scale-[0.98]`
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// `text-[20px] text-ink/60`
struct Eyebrow: View {
    let text: String
    var onDark = false
    var body: some View {
        Text(text).font(.wave(20)).foregroundStyle(onDark ? Theme.paper.opacity(0.5) : Theme.ink.opacity(0.6))
    }
}

/// `text-[36px] leading-[1.15] font-medium tracking-tight`, muted lead + strong close.
struct Heading: View {
    let muted: String
    let strong: String
    var onDark = false
    var body: some View {
        (Text(muted + " ").foregroundStyle(onDark ? Theme.paper.opacity(0.4) : Theme.ink.opacity(0.4))
            + Text(strong).foregroundStyle(onDark ? Theme.paper : Theme.ink))
            .font(.wave(36, .medium)).tracking(-0.9).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `rounded-btn bg-ink px-5 py-2.5 font-medium text-paper shadow-[6px_8px_12px]`, lifts on hover.
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var onDark = false
    var large = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: 18, color: onDark ? Theme.ink : Theme.paper) }
                Text(title)
            }
            .font(.wave(16, .medium))
            .foregroundStyle(onDark ? Theme.ink : Theme.paper)
            .padding(.horizontal, large ? 28 : 20).padding(.vertical, large ? 16 : 10)
            .background(onDark ? Theme.paper : Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
            .shadow(color: Theme.ink.opacity(onDark ? 0 : 0.25), radius: 6, x: 6, y: 8)
            .offset(y: hover ? -2 : 0)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.2), value: hover)
    }
}

/// `rounded-btn bg-ink/5 px-5 py-3 font-medium`
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.wave(16, .medium)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Theme.ink.opacity(hover ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.2), value: hover)
    }
}

/// `px-4 py-2 text-sm rounded-btn bg-ink/[0.05] text-ink/70`; selected = ink on paper; on dark = outlined.
struct Chip: View {
    let text: String
    var selected = false
    var onDark = false
    var body: some View {
        Text(text).font(.wave(14))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundStyle(selected || onDark ? Theme.paper : Theme.ink.opacity(0.7))
            .background(selected ? Theme.ink : onDark ? Color.clear : Theme.chip, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
            .overlay {
                if onDark, !selected { RoundedRectangle(cornerRadius: Theme.radiusButton).stroke(Theme.paper.opacity(0.4)) }
            }
    }
}

/// Brand-green dot with the hero's ping ring.
struct LiveDot: View {
    @State private var ping = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        ZStack {
            Circle().fill(Theme.brand).scaleEffect(ping ? 2.6 : 1).opacity(ping ? 0 : 0.6)
            Circle().fill(Theme.brand)
        }
        .frame(width: 8, height: 8)
        .onAppear { if !reduce { withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { ping = true } } }
    }
}

struct Grain: View {
    var body: some View {
        Image(nsImage: Theme.grain).resizable(resizingMode: .tile).opacity(0.5).allowsHitTesting(false)
    }
}

/// `rounded-[40px] bg-black` with `.grain`, like the process and final CTA sections.
struct DarkSection<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { ZStack { Theme.black; Grain() } }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSection))
    }
}

/// Fade-and-rise on appear, `{ opacity: 0, y: 24 }` to visible with the site's easing.
struct Rise: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 24)
            .onAppear { withAnimation(Theme.curve.delay(delay)) { shown = true } }
    }
}

/// Text input as a soft surface pill, `rounded-btn bg-ink/[0.04] px-5 py-3`.
struct WaveField: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).font(.wave(16))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
    }
}

extension View {
    func rise(_ delay: Double = 0) -> some View { modifier(Rise(delay: delay)) }
    func waveField() -> some View { modifier(WaveField()) }
    /// Nested-card frame: `rounded-3xl bg-ink/[0.04] p-1.5`.
    func cardFrame(dark: Bool = false) -> some View {
        padding(6)
            .background(dark ? Theme.ink : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
            .shadow(color: Theme.ink.opacity(dark ? 0.4 : 0), radius: 16, x: 16, y: 24)
    }
    /// Inner block of a nested card: `rounded-[18px] bg-paper`.
    func cardBlock(_ fill: Color = Theme.paper) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
    }
}
