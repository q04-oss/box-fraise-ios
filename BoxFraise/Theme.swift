import SwiftUI
import UIKit

// MARK: - Color palette

struct FraiseColors: Sendable {
    let background: Color
    let card: Color
    let text: Color
    let muted: Color
    let border: Color
    let searchBg: Color

    // Card (#F7F5F2) is warm off-white against pure white (#FFFFFF) background — depth without
    // harsh contrast. Border (#E5E1DA) is warm gray to avoid the blue-shifted system separator.
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

// MARK: - Semantic colours (referenced throughout; never inline hex)

extension Color {
    static let fraiseGreen  = Color(hex: "4CAF50")
    static let fraiseRed    = Color(hex: "C0392B")
    static let fraiseOrange = Color(hex: "E67E22")
    static let fraiseBlue   = Color(hex: "2196F3")
}

// MARK: - Radius scale

enum Radius {
    static let sheet:  CGFloat = 24   // modal sheets — matches system sheet corner radius
    static let callout: CGFloat = 20  // map callout cards — larger feels physical, not digital
    static let card:   CGFloat = 14   // cards, containers, panels
    static let button: CGFloat = 12   // full-width action buttons, list cards
    static let field:  CGFloat = 10   // text fields, search bars
    static let chip:   CGFloat = 8    // inline quoted content, small tags
}

// MARK: - Divider opacity

enum Divide {
    static let row:     Double = 0.4  // between list rows
    static let section: Double = 0.6  // between distinct sections
}

// MARK: - Animation vocabulary

extension Animation {
    // Primary navigation transitions — panel changes, sheet content swaps.
    static let fraiseSpring  = Animation.spring(response: 0.28, dampingFraction: 0.88)
    // Physical element appearance — map callouts, banners, overlays.
    // Longer response than fraiseSpring: presence should feel physical, not digital.
    static let fraiseCallout = Animation.spring(response: 0.35)
    // Skeleton shimmer — easeInOut so the pulse feels organic, not mechanical.
    static let fraiseSkeleton = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
}

// MARK: - Transition vocabulary

extension AnyTransition {
    // Primary panel insertion/removal used by SheetContent.
    static let fraisePanelTransition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 18)),
        removal:   .opacity.combined(with: .offset(y: -6))
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

// MARK: - Date formatting

enum FraiseDateFormatter {
    // Single pair of static formatters — ISO8601DateFormatter is thread-safe after configuration.
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Returns nil for any string that is not a valid ISO 8601 date.
    static func date(from iso: String) -> Date? {
        // Fast path: server sends ISO 8601 with fractional seconds in the vast majority of responses.
        if let d = fractional.date(from: iso) { return d }
        // Fallback: legacy responses omit fractional seconds.
        return standard.date(from: iso)
    }

    /// "March 15, 2025" — purchase records, event history
    static func long(_ iso: String) -> String {
        guard let d = date(from: iso) else { return iso }
        return d.formatted(.dateTime.month(.wide).day().year())
    }

    /// "March 15" — met dates, short references
    static func medium(_ iso: String) -> String {
        guard let d = date(from: iso) else { return "" }
        return d.formatted(.dateTime.month(.wide).day())
    }

    /// "Mon, Mar 15" — compact date cards, no time
    static func short(_ iso: String) -> String {
        guard let d = date(from: iso) else { return iso }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Wednesday, March 15, 7:00 PM" — dinner invitations, formal events
    static func event(_ iso: String) -> String {
        guard let d = date(from: iso) else { return iso }
        return d.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
    }

    /// "Mon, Mar 15, 7:00 PM" — compact event with time
    static func compact(_ iso: String) -> String {
        guard let d = date(from: iso) else { return iso }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    /// "7:00 PM" today · "Mar 15" any other day — thread row timestamps
    static func thread(_ iso: String) -> String {
        guard let d = date(from: iso) else { return "" }
        return Calendar.current.isDateInToday(d)
            ? d.formatted(.dateTime.hour().minute())
            : d.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "7:00 PM" — message bubble timestamps
    static func time(_ iso: String) -> String {
        guard let d = date(from: iso) else { return "" }
        return d.formatted(.dateTime.hour().minute())
    }
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

// MARK: - Shared small components

/// Green presence dot used in the messages status line and contact rows.
struct StatusDot: View {
    var body: some View {
        Circle().fill(Color.fraiseGreen).frame(width: 7, height: 7)
    }
}

// MARK: - Panel header

/// Standard panel header used by every sheet panel.
/// Eliminates the repeated HStack { FraiseBackButton; Spacer; Text; Spacer; trailing } pattern.
struct PanelHeader<Trailing: View>: View {
    @Environment(\.fraiseColors) private var c
    let title: String
    let onBack: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            FraiseBackButton(action: onBack)
            Spacer()
            Text(title)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(c.text)
            Spacer()
            trailing()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
    }
}

extension PanelHeader where Trailing == Color {
    init(title: String, onBack: @escaping () -> Void) {
        self.title   = title
        self.onBack  = onBack
        self.trailing = { Color.clear.frame(width: 40) }
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

// MARK: - Skeleton

enum SkeletonStyle {
    case narrow  // short label, e.g. a name
    case wide    // long label, e.g. a title or order description
}

struct FraiseSkeletonRow: View {
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let style: SkeletonStyle

    init(style: SkeletonStyle = .narrow) { self.style = style }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(shimmer ? 0.12 : 0.07))
                    .frame(width: style == .wide ? 160 : 120, height: 13)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(shimmer ? 0.08 : 0.04))
                    .frame(width: 80, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(shimmer ? 0.1 : 0.06))
                .frame(width: 44, height: 13)
        }
        .padding(Spacing.md)
        .background(Color.gray.opacity(shimmer ? 0.04 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            guard !reduceMotion else { shimmer = true; return }
            withAnimation(.fraiseSkeleton) { shimmer = true }
        }
        .accessibilityHidden(true)
    }
}

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

// MARK: - ViewState

/// Uniform loading/error/data lifecycle for all data-fetching views.
/// Replaces the `@State var loading: Bool` + silent-nil-on-error pattern.
enum ViewState<T> {
    /// Initial state before any load has been requested.
    /// Distinct from .loading (in flight) and .loaded (complete).
    case idle
    case loading
    case loaded(T)
    case failed(String)

    var isLoading: Bool  { if case .loading     = self { return true  }; return false }
    var value:     T?    { if case .loaded(let v) = self { return v   }; return nil   }
    var errorMessage: String? {
        if case .failed(let m) = self { return m }; return nil
    }
}

// MARK: - Error view

struct FraiseErrorView: View {
    @Environment(\.fraiseColors) private var c
    let message: String
    // @MainActor — retry always updates @State, which must happen on the main actor.
    var retry: (@MainActor () async -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28)).foregroundStyle(c.border)
            Text(message)
                .font(.mono(12)).foregroundStyle(c.muted)
                .multilineTextAlignment(.center)
            if let retry {
                Button { Task { await retry() } } label: {
                    Text("retry")
                        .font(.mono(12)).foregroundStyle(c.text)
                        .padding(.horizontal, Spacing.md).padding(.vertical, 10)
                        .background(c.card)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .overlay(RoundedRectangle(cornerRadius: Radius.button)
                            .strokeBorder(c.border, lineWidth: 0.5))
                }
                .accessibilityLabel("retry")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Button styles

struct FraisePrimaryButtonStyle: ButtonStyle {
    @Environment(\.fraiseColors) private var c

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(13, weight: .medium))
            .foregroundStyle(c.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(c.text.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct FraiseSecondaryButtonStyle: ButtonStyle {
    @Environment(\.fraiseColors) private var c

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(13))
            .foregroundStyle(c.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(c.searchBg.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    func fraisePrimaryButton() -> some View { buttonStyle(FraisePrimaryButtonStyle()) }
    func fraiseSecondaryButton() -> some View { buttonStyle(FraiseSecondaryButtonStyle()) }
}

// MARK: - Card modifier

struct FraiseCardModifier: ViewModifier {
    @Environment(\.fraiseColors) private var c
    var highlighted: Bool

    func body(content: Content) -> some View {
        content
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(highlighted ? c.text.opacity(0.25) : c.border, lineWidth: 0.5))
    }
}

extension View {
    func fraiseCard(highlighted: Bool = false) -> some View {
        modifier(FraiseCardModifier(highlighted: highlighted))
    }
}
