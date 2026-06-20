import SwiftUI

enum AtlassianTheme {
    static let blue = Color(hex: 0x0052CC)
    static let bluePressed = Color(hex: 0x0747A6)
    static let background = Color.dynamic(light: 0xF4F5F7, dark: 0x0F1117)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1B1F29)
    static let secondarySurface = Color.dynamic(light: 0xFAFBFC, dark: 0x242936)
    static let text = Color.dynamic(light: 0x172B4D, dark: 0xF4F5F7)
    static let mutedText = Color.dynamic(light: 0x6B778C, dark: 0xA5ADBA)
    static let border = Color.dynamic(light: 0xDFE1E6, dark: 0x303849)
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

    static func dynamic(light: UInt, dark: UInt) -> Color {
        #if os(iOS)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
        #else
        return Color(hex: light)
        #endif
    }
}

#if os(iOS)
extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif

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
    @EnvironmentObject private var appSettings: AppSettings

    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(appSettings.fontChoice == .system ? .largeTitle.weight(.bold) : appSettings.fontChoice.font(size: 34 * appSettings.fontScale, relativeTo: .largeTitle))
                .foregroundStyle(AtlassianTheme.text)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(appSettings.subheadlineFont)
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
    @EnvironmentObject private var appSettings: AppSettings

    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AtlassianTheme.mutedText)
            Text(title)
                .font(appSettings.headlineFont)
                .foregroundStyle(AtlassianTheme.text)
            Text(message)
                .font(appSettings.subheadlineFont)
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
