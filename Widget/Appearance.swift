import WidgetKit
import SwiftUI
import AppIntents

/// Every Wave widget takes one option in "Edit Widget": follow the system, or force light or dark.
enum WidgetAppearance: String, AppEnum {
    case auto, light, dark
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Background")
    static let caseDisplayRepresentations: [WidgetAppearance: DisplayRepresentation] = [
        .auto: "Follow the system", .light: "White", .dark: "Black",
    ]
}

struct AppearanceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Appearance"
    static let description = IntentDescription("White or black background.")
    @Parameter(title: "Background", default: .auto) var appearance: WidgetAppearance
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
