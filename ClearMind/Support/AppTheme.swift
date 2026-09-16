import AppKit
import SwiftUI

enum CMTheme {
    static let pageMaxWidth: CGFloat = 1060
    static let pagePadding: CGFloat = 44
    static let sectionSpacing: CGFloat = 38
    static let rowVerticalPadding: CGFloat = 15

    static let canvas = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor).opacity(0.68)
    static let quietFill = Color(nsColor: .controlBackgroundColor)
    static let islandSurface = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let cardSurface = Color(nsColor: .textBackgroundColor)

    static let paletteKeys = ["sage", "clay", "denim", "ochre", "plum", "slate"]

    static func color(for key: String) -> Color {
        switch key {
        case "clay": Color(red: 0.67, green: 0.38, blue: 0.30)
        case "denim": Color(red: 0.25, green: 0.43, blue: 0.61)
        case "ochre": Color(red: 0.66, green: 0.49, blue: 0.19)
        case "plum": Color(red: 0.48, green: 0.34, blue: 0.49)
        case "slate": Color(red: 0.36, green: 0.42, blue: 0.46)
        default: Color(red: 0.31, green: 0.49, blue: 0.39)
        }
    }

    static func statusColor(_ status: WorkstreamStatus) -> Color {
        switch status {
        case .planned: color(for: "slate")
        case .inProgress: color(for: "denim")
        case .completed: color(for: "sage")
        }
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? CMTheme.quietFill.opacity(0.65) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(nsColor: .textBackgroundColor))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(CMTheme.textPrimary.opacity(configuration.isPressed ? 0.72 : 0.92))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

extension View {
    func calmTextField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(CMTheme.quietFill.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(CMTheme.separator, lineWidth: 0.7)
            }
    }
}
