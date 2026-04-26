import SwiftUI

// MARK: - PrimaryButton

struct PrimaryButton: View {
    let label: String
    var loading: Bool = false
    let action: () -> Void

    @Environment(\.fraiseColors) var c

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(label)
                    .font(.mono(12))
                    .foregroundStyle(c.background)
                    .opacity(loading ? 0 : 1)
                if loading {
                    ProgressView()
                        .tint(c.background)
                        .scaleEffect(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(c.text)
            .clipShape(Capsule())
        }
        .disabled(loading)
        .opacity(loading ? 0.7 : 1)
    }
}

// MARK: - GhostButton

struct GhostButton: View {
    let label: String
    let action: () -> Void

    @Environment(\.fraiseColors) var c

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.mono(12))
                .foregroundStyle(c.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .overlay(Capsule().stroke(c.border, lineWidth: 1))
        }
    }
}

// MARK: - Card

struct FraiseCard<Content: View>: View {
    @Environment(\.fraiseColors) var c
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(c.border, lineWidth: 0.5)
            )
    }
}

// MARK: - StatRow

struct StatRow: View {
    let label: String
    let value: String
    var topBorder: Bool = true

    @Environment(\.fraiseColors) var c

    var body: some View {
        HStack {
            Text(label)
                .font(.mono(12))
                .foregroundStyle(c.muted)
            Spacer()
            Text(value)
                .font(.mono(12))
                .foregroundStyle(c.text)
        }
        .padding(Spacing.md)
        .overlay(alignment: .top) {
            if topBorder {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(c.border)
            }
        }
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let text: String
    @Environment(\.fraiseColors) var c

    var body: some View {
        Text(text.uppercased())
            .font(.mono(10))
            .foregroundStyle(c.muted)
            .tracking(1.5)
    }
}

// MARK: - ErrorText

struct ErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.mono(12))
            .foregroundStyle(Color(hex: "C0392B"))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - MonoField (labelled text input)

struct MonoField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)? = nil

    @Environment(\.fraiseColors) var c

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(autocapitalization)
                }
            }
            .font(.mono(14))
            .foregroundStyle(c.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(c.searchBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(c.border, lineWidth: 1))
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
        }
    }
}

// MARK: - OrDivider

struct OrDivider: View {
    @Environment(\.fraiseColors) var c

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
            Text("or")
                .font(.mono(11))
                .foregroundStyle(c.muted)
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
        }
    }
}
