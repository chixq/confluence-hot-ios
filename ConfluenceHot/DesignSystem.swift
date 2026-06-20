import SwiftUI

enum AtlassianTheme {
    static let blue = Color(hex: 0x0052CC)
    static let bluePressed = Color(hex: 0x0747A6)
    static let background = Color.dynamic(light: 0xEEF3FA, dark: 0x0B0F17)
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
            .background(
                LinearGradient(
                    colors: [
                        configuration.isPressed ? AtlassianTheme.bluePressed : AtlassianTheme.blue,
                        Color(hex: 0x2684FF)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: AtlassianTheme.blue.opacity(configuration.isPressed ? 0.12 : 0.28), radius: 18, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(configuration.isPressed ? AtlassianTheme.bluePressed : AtlassianTheme.blue)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct LiquidBackground: View {
    var body: some View {
        ZStack {
            AtlassianTheme.background
            LinearGradient(
                colors: [
                    Color.white.opacity(0.32),
                    AtlassianTheme.blue.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct LiquidGlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 26
    var isSelected = false
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? AtlassianTheme.blue.opacity(0.14) : Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.58),
                                AtlassianTheme.border.opacity(0.52),
                                Color.white.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            )
            .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 26, isSelected: Bool = false, padding: CGFloat = 0) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius, isSelected: isSelected, padding: padding))
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
        .liquidGlassPanel(cornerRadius: 28)
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

    @ViewBuilder
    func liquidNavigationChrome() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func liquidTabBarChrome() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        #else
        self
        #endif
    }
}
