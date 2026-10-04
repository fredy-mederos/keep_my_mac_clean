import CleanerCore
import SwiftUI

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

/// Small capsule label such as "Review" or "To Trash".
struct Tag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
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
        .foregroundStyle(.secondary)
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
                .foregroundStyle(state == .off ? Color.secondary.opacity(0.6) : Color.accentColor)
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
    func card(cornerRadius: CGFloat = 12, fill: Color = Color.primary.opacity(0.045)) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill))
    }
}
