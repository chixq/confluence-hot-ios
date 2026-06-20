import SwiftUI

enum AtlassianTheme {
    static let blue = Color(hex: 0x0052CC)
    static let bluePressed = Color(hex: 0x0747A6)
    static let background = Color(hex: 0xF4F5F7)
    static let surface = Color.white
    static let text = Color(hex: 0x172B4D)
    static let mutedText = Color(hex: 0x6B778C)
    static let border = Color(hex: 0xDFE1E6)
    static let green = Color(hex: 0x36B37E)
    static let yellow = Color(hex: 0xFFAB00)
    static let red = Color(hex: 0xDE350B)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.white)
            .background(configuration.isPressed ? AtlassianTheme.bluePressed : AtlassianTheme.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(configuration.isPressed ? AtlassianTheme.bluePressed : AtlassianTheme.blue)
            .background(AtlassianTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AtlassianTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AtlassianTheme.text)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AtlassianTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AtlassianTheme.mutedText)
            Text(title)
                .font(.headline)
                .foregroundStyle(AtlassianTheme.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AtlassianTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(24)
    }
}

extension View {
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
