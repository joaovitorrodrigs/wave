import SwiftUI
import AppKit

/// Tokens from wavestudio.pro: ink/paper, green as support, violet as accent, Instrument Sans everywhere.
enum Theme {
    static let ink = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let brand = Color(red: 0, green: 0xC0 / 255, blue: 0x47 / 255)
    static let violet = Color(red: 0x74 / 255, green: 0x30 / 255, blue: 0xF7 / 255)
    /// Paper in light mode, ink in dark mode.
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1) : .white
    })
    static let card = Color.primary.opacity(0.04)
    static let radiusCard: CGFloat = 24

    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "InstrumentSans", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    static func wave(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Instrument Sans", size: size).weight(weight)
    }
    static let waveTitle = wave(28, .semibold)
    static let waveTitle3 = wave(18, .semibold)
    static let waveHeadline = wave(15, .semibold)
    static let waveBody = wave(14)
    static let waveCaption = wave(12)
}
