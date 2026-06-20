import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum AtlassianTheme {
    static let blue = Color(hex: 0x0C66E4)
    static let bluePressed = Color(hex: 0x0055CC)
    static let sky = Color(hex: 0x1D7AFC)
    static let teal = Color(hex: 0x00A3BF)
    static let background = Color.dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let groupedBackground = Color.dynamic(light: 0xF2F2F7, dark: 0x000000)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let secondarySurface = Color.dynamic(light: 0xF2F2F7, dark: 0x111111)
    static let text = Color.dynamic(light: 0x172B4D, dark: 0xD8DEE9)
    static let mutedText = Color.dynamic(light: 0x626F86, dark: 0x758195)
    static let border = Color.dynamic(light: 0xDFE1E6, dark: 0x1F1F1F)
    static let separator = Color.dynamic(light: 0xE5E5EA, dark: 0x1F1F1F)
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
            .background(configuration.isPressed ? AtlassianTheme.bluePressed : AtlassianTheme.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .background(AtlassianTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AtlassianTheme.separator, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct LiquidBackground: View {
    var body: some View {
        AtlassianTheme.background.ignoresSafeArea()
    }
}

private struct LiquidGlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 26
    var isSelected = false
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(isSelected ? AtlassianTheme.blue.opacity(0.10) : AtlassianTheme.surface, in: RoundedRectangle(cornerRadius: min(cornerRadius, 12), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: min(cornerRadius, 12), style: .continuous)
                    .stroke(AtlassianTheme.separator, lineWidth: 0.5)
            )
    }
}

private struct LiquidFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AtlassianTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                .font(appSettings.fontChoice == .system ? .title.weight(.semibold) : appSettings.fontChoice.font(size: 28 * appSettings.fontScale, relativeTo: .title))
                .foregroundStyle(AtlassianTheme.text)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(appSettings.subheadlineFont)
                    .foregroundStyle(AtlassianTheme.mutedText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
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
                .foregroundStyle(AtlassianTheme.mutedText)
                .frame(width: 58, height: 58)
                .background(AtlassianTheme.secondarySurface, in: Circle())
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
        .background(AtlassianTheme.background)
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
            .background(tint.opacity(0.12), in: Circle())
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

struct AvatarView: View {
    let name: String?
    var tint: Color = AtlassianTheme.mutedText
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
            Text(initials)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        let cleaned = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "?" }
        if let first = cleaned.first {
            return String(first).uppercased()
        }
        return "?"
    }
}

struct AuthenticatedAvatarView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    let name: String?
    let path: String?
    var tint: Color = AtlassianTheme.mutedText
    var size: CGFloat = 44

    @State private var image: PlatformImage?
    @State private var loadedPath: String?

    var body: some View {
        Group {
            if let image {
                platformImage(image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                AvatarView(name: name, tint: tint, size: size)
            }
        }
        .task(id: path ?? "") {
            await load()
        }
    }

    private func load() async {
        guard loadedPath != path else { return }
        loadedPath = path
        image = nil
        guard let path, !path.isEmpty,
              let client = sessionStore.client,
              let url = resolve(path: path, baseURL: client.baseURL) else { return }

        do {
            let payload = try await client.fetchData(url: url)
            #if os(iOS)
            image = UIImage(data: payload.data)
            #else
            image = NSImage(data: payload.data)
            #endif
        } catch {
            image = nil
        }
    }

    private func resolve(path: String, baseURL: URL) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    @ViewBuilder
    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}

#if os(iOS)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

enum TextHighlighter {
    static func attributed(_ text: String, query: String?) -> AttributedString {
        var attributed = AttributedString(text)
        let term = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !term.isEmpty else { return attributed }

        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex) {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed),
               let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper].backgroundColor = AtlassianTheme.yellow.opacity(0.38)
                attributed[lower..<upper].foregroundColor = AtlassianTheme.text
            }
            searchStart = range.upperBound
        }
        return attributed
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
            .toolbarBackground(AtlassianTheme.background, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func liquidTabBarChrome() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(AtlassianTheme.surface, for: .tabBar)
        #else
        self
        #endif
    }
}
