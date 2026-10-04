import AppKit
import CleanerCore
import SwiftUI

/// Text colors with separate light and dark shades, each at least 5:1 contrast on the popover's background,
/// its cards and selected rows (WCAG asks 4.5:1 for small text). The system `.secondary` was ~3.7:1 in light mode.
enum Palette {
    static let secondaryText = Color(light: NSColor.black.withAlphaComponent(0.72), dark: NSColor.white.withAlphaComponent(0.74))
    static let blue = Color(light: 0x0848A6, dark: 0x8CC2FF)
    static let orange = Color(light: 0x8A4600, dark: 0xFFB861)
    static let red = Color(light: 0x9C1B14, dark: 0xFF8F85)
    static let purple = Color(light: 0x6A2DB0, dark: 0xCDA8FF)
    static let green = Color(light: 0x135C24, dark: 0x84E39A)

    /// Mostly opaque, with a hint of the wallpaper: the menu bar window is translucent, and a colorful wallpaper behind it washed out text.
    static let popoverBackground = Color(nsColor: .windowBackgroundColor).opacity(0.90)
    static let card = Color.primary.opacity(0.055)
    static let cardHover = Color.primary.opacity(0.085)
}

extension Color {
    /// A color that follows the light or dark appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    init(light: UInt32, dark: UInt32) {
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(light: color(light), dark: color(dark))
    }
}

extension CleanupCategory {
    var tint: Color {
        switch id {
        case "projects": .blue
        case "xcode": .indigo
        case "android": .green
        case "packages": .brown
        case "ides": .purple
        case "docker": .cyan
        case "files": .teal
        default: .gray
        }
    }
}

extension Safety {
    var tint: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .personal: .blue
        }
    }
}

extension CostLevel {
    /// For text: readable shades from the palette.
    var textColor: Color {
        switch self {
        case .rebuild: Palette.secondaryText
        case .redownload: Palette.blue
        case .loseOption: Palette.orange
        case .dataLoss: Palette.red
        }
    }

    var tint: Color {
        switch self {
        case .rebuild: .secondary
        case .redownload: .blue
        case .loseOption: .orange
        case .dataLoss: .red
        }
    }

    var symbol: String {
        switch self {
        case .rebuild: "hammer"
        case .redownload: "arrow.down.circle"
        case .loseOption: "arrow.uturn.backward.circle"
        case .dataLoss: "exclamationmark.triangle.fill"
        }
    }
}

extension AppModel.SpaceStatus {
    var tint: Color {
        switch self {
        case .good: .green
        case .tight: .orange
        case .low: .red
        }
    }
}

/// Rounded app-icon style square with a white symbol, like System Settings.
struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Small capsule label such as "Review" or "To Trash". Pass a palette color so the text stays readable.
struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Borderless round icon button with a hover highlight.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(isHovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.secondaryText)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

struct CheckBox: View {
    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(state == .off ? Palette.secondaryText.opacity(0.75) : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .on ? "Selected" : state == .mixed ? "Partly selected" : "Not selected")
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.circle.fill"
        case .mixed: "minus.circle.fill"
        case .off: "circle"
        }
    }
}

extension View {
    /// Main call to action: Liquid Glass on macOS 26+, a bordered capsule before.
    @ViewBuilder
    func primaryActionStyle(tint: Color = .accentColor) -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(tint).controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).tint(tint).buttonBorderShape(.capsule).controlSize(.large)
        }
    }

    @ViewBuilder
    func secondaryActionStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass).controlSize(.large)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
        }
    }

    /// Soft rounded card background used for categories and chips.
    func card(cornerRadius: CGFloat = 12, fill: Color = Palette.card) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill))
    }
}
