import AppKit
import SwiftUI

enum AppearanceTheme: String, CaseIterable, Identifiable {
    case warmTerracotta, mistyBlue, sageGreen, mutedLavender, slateIndigo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmTerracotta: "暖陶橙"
        case .mistyBlue: "雾蓝灰"
        case .sageGreen: "鼠尾草绿"
        case .mutedLavender: "薰衣草灰"
        case .slateIndigo: "石墨蓝"
        }
    }

    var shortcutNumber: String {
        switch self {
        case .warmTerracotta: "1"
        case .mistyBlue: "2"
        case .sageGreen: "3"
        case .mutedLavender: "4"
        case .slateIndigo: "5"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .warmTerracotta:
            ThemePalette(backgroundHex: "#FAF9F7", sidebarHex: "#F0EFEC", surfaceHex: "#FFFFFF",
                         borderHex: "#D7D5D0", textHex: "#292724", mutedTextHex: "#6C6964",
                         primaryHex: "#D97757", activeHex: "#E9E7E2", primaryFillHex: "#AB5E45")
        case .mistyBlue:
            ThemePalette(backgroundHex: "#F8FAFC", sidebarHex: "#EEF2F6", surfaceHex: "#FFFFFF",
                         borderHex: "#D7E0E9", textHex: "#263548", mutedTextHex: "#606B78",
                         primaryHex: "#5C7FA6", activeHex: "#DEE7F2", primaryFillHex: "#56769A")
        case .sageGreen:
            ThemePalette(backgroundHex: "#F9FAF7", sidebarHex: "#EEF2EB", surfaceHex: "#FFFFFF",
                         borderHex: "#D9E1D5", textHex: "#2D382F", mutedTextHex: "#636E62",
                         primaryHex: "#728D76", activeHex: "#DFE8DC", primaryFillHex: "#627965")
        case .mutedLavender:
            ThemePalette(backgroundHex: "#FBF9FC", sidebarHex: "#F2EEF6", surfaceHex: "#FFFFFF",
                         borderHex: "#E3DAE9", textHex: "#383040", mutedTextHex: "#6E6774",
                         primaryHex: "#9076AA", activeHex: "#EAE1F0", primaryFillHex: "#806997")
        case .slateIndigo:
            ThemePalette(backgroundHex: "#F7F8FA", sidebarHex: "#ECEFF3", surfaceHex: "#FFFFFF",
                         borderHex: "#D6DAE1", textHex: "#292E3A", mutedTextHex: "#646A74",
                         primaryHex: "#576C90", activeHex: "#DFE5EF", primaryFillHex: "#576C90")
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let storageKey = "appearanceTheme"

    @Published private(set) var selection: AppearanceTheme
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("--uitesting-reset-theme") {
            defaults.removeObject(forKey: Self.storageKey)
        }
        selection = AppearanceTheme(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .warmTerracotta
    }

    func select(_ theme: AppearanceTheme) {
        guard selection != theme else { return }
        selection = theme
        defaults.set(theme.rawValue, forKey: Self.storageKey)
    }
}

struct ThemePalette {
    let backgroundHex: String
    let sidebarHex: String
    let surfaceHex: String
    let borderHex: String
    let textHex: String
    let mutedTextHex: String
    let primaryHex: String
    let activeHex: String
    let primaryFillHex: String

    var primaryHoverHex: String { Self.mix(primaryFillHex, "#000000", amount: 0.08) }
    var primaryPressedHex: String { Self.mix(primaryFillHex, "#000000", amount: 0.16) }

    var canvas: Color { Self.color(backgroundHex) }
    var sidebar: Color { Self.color(sidebarHex) }
    var cardSurface: Color { Self.color(surfaceHex) }
    var textPrimary: Color { Self.color(textHex) }
    var textSecondary: Color { Self.color(mutedTextHex) }
    var textTertiary: Color { Self.color(mutedTextHex) }
    var separator: Color { Self.color(borderHex) }
    var primary: Color { Self.color(primaryHex) }
    var primaryFill: Color { Self.color(primaryFillHex) }
    var primaryHover: Color { Self.color(primaryHoverHex) }
    var primaryPressed: Color { Self.color(primaryPressedHex) }
    var active: Color { Self.color(activeHex) }
    var quietFill: Color { active }
    var islandSurface: Color { cardSurface }
    var toolbarControlSurface: Color { cardSurface }
    var currentScheduleHighlight: Color { Self.color(Self.mix(surfaceHex, primaryHex, amount: 0.13)) }
    var primarySoft: Color { currentScheduleHighlight }
    var hover: Color { Self.color(Self.mix(sidebarHex, primaryHex, amount: 0.07)) }
    var focus: Color { primaryFill }
    var danger: Color { contentTextColor(for: "clay") }
    var success: Color { contentTextColor(for: "sage") }

    func contentHex(for key: String) -> String {
        Self.mix(Self.contentBaseHex[key] ?? Self.contentBaseHex["sage"]!, primaryHex, amount: 0.2)
    }

    func contentTintBackgroundHex(for key: String) -> String {
        Self.mix(backgroundHex, contentHex(for: key), amount: 0.2)
    }

    func contentTextHex(for key: String) -> String {
        var rgb = Self.rgb(contentHex(for: key))
        while Self.contrast(Self.hex(rgb), contentTintBackgroundHex(for: key)) < 4.5 {
            rgb = RGB(r: max(0, rgb.r - 2), g: max(0, rgb.g - 2), b: max(0, rgb.b - 2))
        }
        return Self.hex(rgb)
    }

    func contentOnColorHex(for key: String) -> String {
        let background = contentHex(for: key)
        if Self.contrast("#FFFFFF", background) >= 4.5 { return "#FFFFFF" }
        if Self.contrast(textHex, background) >= 4.5 { return textHex }
        return "#000000"
    }

    func color(for key: String) -> Color { Self.color(contentHex(for: key)) }
    func contentTextColor(for key: String?) -> Color { Self.color(contentTextHex(for: key ?? "ochre")) }
    func contentOnColor(for key: String) -> Color { Self.color(contentOnColorHex(for: key)) }
    func milestoneHex(for key: String?) -> String {
        contentHex(for: key.flatMap { CMTheme.paletteKeys.contains($0) ? $0 : nil } ?? "ochre")
    }
    func milestoneColor(for key: String?) -> Color { Self.color(milestoneHex(for: key)) }

    private static let contentBaseHex = [
        "sage": "#4F7D63", "clay": "#AB614D", "denim": "#406E9C",
        "ochre": "#A87D30", "plum": "#7A577D", "slate": "#5C6B75"
    ]

    private struct RGB {
        let r: Int
        let g: Int
        let b: Int
    }

    private static func rgb(_ hex: String) -> RGB {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return RGB(r: value >> 16 & 0xFF, g: value >> 8 & 0xFF, b: value & 0xFF)
    }

    private static func hex(_ rgb: RGB) -> String {
        String(format: "#%02X%02X%02X", rgb.r, rgb.g, rgb.b)
    }

    private static func mix(_ first: String, _ second: String, amount: Double) -> String {
        let lhs = rgb(first)
        let rhs = rgb(second)
        return hex(RGB(
            r: Int((Double(lhs.r) * (1 - amount) + Double(rhs.r) * amount).rounded()),
            g: Int((Double(lhs.g) * (1 - amount) + Double(rhs.g) * amount).rounded()),
            b: Int((Double(lhs.b) * (1 - amount) + Double(rhs.b) * amount).rounded())
        ))
    }

    private static func contrast(_ first: String, _ second: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let value = rgb(hex)
            let channels = [value.r, value.g, value.b].map { component -> Double in
                let channel = Double(component) / 255
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let values = [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }

    static func color(_ hex: String) -> Color {
        let components = rgb(hex)
        return Color(.sRGB, red: Double(components.r) / 255,
                     green: Double(components.g) / 255, blue: Double(components.b) / 255,
                     opacity: 1)
    }
}

extension EnvironmentValues {
    @Entry var cmPalette: ThemePalette = AppearanceTheme.warmTerracotta.palette
}

enum CMTheme {
    static let pageMaxWidth: CGFloat = 1060
    static let pagePadding: CGFloat = 32
    static let sectionSpacing: CGFloat = 32
    static let rowVerticalPadding: CGFloat = 16
    static let paletteKeys = ["sage", "clay", "denim", "ochre", "plum", "slate"]
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .modifier(QuietButtonFeedback(isPressed: configuration.isPressed))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .modifier(PrimaryButtonFeedback(isPressed: configuration.isPressed))
    }
}

private struct QuietButtonFeedback: ViewModifier {
    @Environment(\.cmPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .background(isPressed ? palette.active : (isHovered && isEnabled ? palette.hover : Color.clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
            .onHover { isHovered = $0 }
    }
}

private struct PrimaryButtonFeedback: ViewModifier {
    @Environment(\.cmPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isEnabled ? Color.white : palette.textSecondary)
            .background(isEnabled
                        ? (isPressed ? palette.primaryPressed : (isHovered ? palette.primaryHover : palette.primaryFill))
                        : palette.active,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

private struct CalmTextFieldModifier: ViewModifier {
    @Environment(\.cmPalette) private var palette
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(palette.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isFocused ? palette.focus : palette.separator, lineWidth: isFocused ? 1.5 : 1)
            }
    }
}

extension View {
    func calmTextField() -> some View { modifier(CalmTextFieldModifier()) }
}
