import WidgetKit
import SwiftUI

/// Background for every Wave widget, chosen once in the app's Settings and handed over as `widget.json`.
enum WidgetAppearance: String, Codable {
    case auto, light, dark

    static var current: WidgetAppearance {
        guard let data = try? Data(contentsOf: Bridge.dir.appending(path: "widget.json")),
              let value = try? JSONDecoder().decode([String: String].self, from: data)["appearance"] else { return .auto }
        return WidgetAppearance(rawValue: value) ?? .auto
    }
}

extension WidgetTheme {
    static func resolve(_ appearance: WidgetAppearance, scheme: ColorScheme) -> WidgetTheme {
        WidgetTheme(dark: appearance == .dark || (appearance == .auto && scheme == .dark))
    }
}

struct WidgetCanvas: View {
    let appearance: WidgetAppearance
    @Environment(\.colorScheme) private var scheme
    var body: some View { WidgetTheme.resolve(appearance, scheme: scheme).paper }
}
