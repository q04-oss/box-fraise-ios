import SwiftUI
import UIKit

// MARK: - Color palette

struct FraiseColors {
    let background: Color
    let card: Color
    let text: Color
    let muted: Color
    let border: Color
    let searchBg: Color

    static let light = FraiseColors(
        background: Color(hex: "FFFFFF"),
        card:       Color(hex: "F7F5F2"),
        text:       Color(hex: "1C1C1E"),
        muted:      Color(hex: "8E8E93"),
        border:     Color(hex: "E5E1DA"),
        searchBg:   Color(hex: "F0EDE8")
    )

    static let dark = FraiseColors(
        background: Color(hex: "0C0C0E"),
        card:       Color(hex: "1A1A1C"),
        text:       Color(hex: "F2F2F7"),
        muted:      Color(hex: "8A8A8E"),
        border:     Color(hex: "2A2A2E"),
        searchBg:   Color(hex: "1A1A1C")
    )
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Environment key

private struct FraiseColorsKey: EnvironmentKey {
    static let defaultValue = FraiseColors.light
}

extension EnvironmentValues {
    var fraiseColors: FraiseColors {
        get { self[FraiseColorsKey.self] }
        set { self[FraiseColorsKey.self] = newValue }
    }
}

// MARK: - Typography

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - View modifier — inject colors based on color scheme

struct FraiseThemeModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme
    func body(content: Content) -> some View {
        content.environment(\.fraiseColors, scheme == .dark ? .dark : .light)
    }
}

extension View {
    func fraiseTheme() -> some View {
        modifier(FraiseThemeModifier())
    }
}

// MARK: - Haptics

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Shared UI components

struct FraiseEmptyState: View {
    @Environment(\.fraiseColors) private var c
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(c.border)
            Text(title)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(c.muted)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.mono(11))
                    .foregroundStyle(c.border)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, Spacing.lg)
    }
}

struct FraiseBackButton: View {
    @Environment(\.fraiseColors) private var c
    let label: String
    let action: () -> Void
    init(_ label: String = "← back", action: @escaping () -> Void) {
        self.label = label; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(label).font(.mono(12)).foregroundStyle(c.muted)
        }
    }
}

struct FraiseSectionLabel: View {
    @Environment(\.fraiseColors) private var c
    let text: String
    var body: some View {
        Text(text)
            .font(.mono(9))
            .foregroundStyle(c.muted)
            .tracking(1.5)
            .textCase(.uppercase)
    }
}
