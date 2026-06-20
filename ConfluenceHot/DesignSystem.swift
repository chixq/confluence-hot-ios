import SwiftUI

enum AtlassianTheme {
    static let blue = Color(hex: 0x0052CC)
    static let bluePressed = Color(hex: 0x0747A6)
    static let sky = Color(hex: 0x2684FF)
    static let teal = Color(hex: 0x00B8D9)
    static let background = Color.dynamic(light: 0xF6F8FC, dark: 0x080B12)
    static let groupedBackground = Color.dynamic(light: 0xEEF3FA, dark: 0x0D121D)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1B1F29)
    static let secondarySurface = Color.dynamic(light: 0xFAFBFC, dark: 0x242936)
    static let text = Color.dynamic(light: 0x172B4D, dark: 0xF4F5F7)
    static let mutedText = Color.dynamic(light: 0x6B778C, dark: 0xA5ADBA)
    static let border = Color.dynamic(light: 0xDFE1E6, dark: 0x303849)
    static let separator = Color.dynamic(light: 0xD7DCE6, dark: 0x303849)
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
            .padding(.vertical, 13)
            .foregroundStyle(Color.white)
            .background(
                LinearGradient(
                    colors: [
                        configuration.isPressed ? AtlassianTheme.bluePressed : AtlassianTheme.blue,
                        AtlassianTheme.sky
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.40), lineWidth: 1)
            )
            .shadow(color: AtlassianTheme.blue.opacity(configuration.isPressed ? 0.10 : 0.22), radius: 16, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(configuration.isPressed ? AtlassianTheme.bluePressed : AtlassianTheme.blue)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct LiquidBackground: View {
    var body: some View {
        ZStack {
            AtlassianTheme.background
            LinearGradient(
                colors: [
                    Color.white.opacity(0.42),
                    AtlassianTheme.blue.opacity(0.07),
                    AtlassianTheme.teal.opacity(0.04),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    Color.clear,
                    AtlassianTheme.groupedBackground.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? AtlassianTheme.blue.opacity(0.16) : Color.white.opacity(0.08))
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
            .shadow(color: Color.black.opacity(isSelected ? 0.14 : 0.07), radius: isSelected ? 18 : 12, x: 0, y: isSelected ? 10 : 6)
    }
}

private struct LiquidFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AtlassianTheme.separator.opacity(0.55), lineWidth: 0.8)
            )
    }
}

extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 26, isSelected: Bool = false, padding: CGFloat = 0) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius, isSelected: isSelected, padding: padding))
    }

    func liquidField() -> some View {
        modifier(LiquidFieldModifier())
    }
}

struct SectionHeader: View {
    @EnvironmentObject private var appSettings: AppSettings

    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(appSettings.fontChoice == .system ? .largeTitle.weight(.bold) : appSettings.fontChoice.font(size: 34 * appSettings.fontScale, relativeTo: .largeTitle))
                .foregroundStyle(AtlassianTheme.text)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(appSettings.subheadlineFont)
                    .foregroundStyle(AtlassianTheme.mutedText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var appSettings: AppSettings

    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AtlassianTheme.blue)
                .frame(width: 58, height: 58)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
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
        .liquidGlassPanel(cornerRadius: 30)
    }
}

struct IconBadge: View {
    let systemName: String
    var tint: Color = AtlassianTheme.blue

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
            )
    }
}

struct CapsuleMetric: View {
    @EnvironmentObject private var appSettings: AppSettings

    let text: String
    var systemName: String?
    var tint: Color = AtlassianTheme.blue

    var body: some View {
        HStack(spacing: 5) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
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
