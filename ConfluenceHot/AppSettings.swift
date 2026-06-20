import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "日间"
        case .dark: return "夜间"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum InterfaceFontChoice: String, CaseIterable, Identifiable {
    case system
    case lxgw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统字体"
        case .lxgw: return "霞鹜文楷"
        }
    }

    var cssFamily: String {
        switch self {
        case .system:
            return "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif"
        case .lxgw:
            return "\"LXGW WenKai\", \"LXGWWenKai-Regular\", -apple-system, BlinkMacSystemFont, sans-serif"
        }
    }

    func font(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        switch self {
        case .system:
            return .system(size: size)
        case .lxgw:
            return .custom("LXGWWenKai-Regular", size: size, relativeTo: textStyle)
        }
    }
}

enum PopularNotificationFrequency: String, CaseIterable, Identifiable {
    case off
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .daily: return "每天"
        case .weekly: return "每周"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .daily: return 24 * 60 * 60
        case .weekly: return 7 * 24 * 60 * 60
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("appearance.mode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("font.choice") private var fontRaw = InterfaceFontChoice.system.rawValue
    @AppStorage("font.scale") var fontScale = 1.0
    @AppStorage("layout.landscapeSplitEnabled") var landscapeSplitEnabled = true
    @AppStorage("notifications.popular.frequency") private var notificationFrequencyRaw = PopularNotificationFrequency.off.rawValue

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var fontChoice: InterfaceFontChoice {
        get { InterfaceFontChoice(rawValue: fontRaw) ?? .system }
        set { fontRaw = newValue.rawValue }
    }

    var notificationFrequency: PopularNotificationFrequency {
        get { PopularNotificationFrequency(rawValue: notificationFrequencyRaw) ?? .off }
        set { notificationFrequencyRaw = newValue.rawValue }
    }

    var preferredColorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }

    var baseFont: Font {
        fontChoice.font(size: 16 * fontScale, relativeTo: .body)
    }

    var titleFont: Font {
        fontChoice.font(size: 22 * fontScale, relativeTo: .title2)
    }

    var headlineFont: Font {
        fontChoice.font(size: 17 * fontScale, relativeTo: .headline)
    }

    var subheadlineFont: Font {
        fontChoice.font(size: 15 * fontScale, relativeTo: .subheadline)
    }
}
