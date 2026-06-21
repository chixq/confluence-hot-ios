import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RootView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        Group {
            if sessionStore.isLoading && sessionStore.configuration == nil {
                ProgressView()
                    .tint(AtlassianTheme.blue)
            } else if sessionStore.isSignedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(appSettings.preferredColorScheme)
    }
}

struct LoginView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            IconBadge(systemName: "flame.fill", tint: Color(hex: 0xA15C00))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Confluence 热门")
                                    .font(appSettings.fontChoice == .system ? .largeTitle.weight(.bold) : appSettings.fontChoice.font(size: 34 * appSettings.fontScale, relativeTo: .largeTitle))
                                    .foregroundStyle(AtlassianTheme.text)
                                Text("连接 Server 或 Data Center 站点")
                                    .font(appSettings.subheadlineFont)
                                    .foregroundStyle(AtlassianTheme.mutedText)
                            }
                        }

                        HStack(spacing: 8) {
                            CapsuleMetric(text: "热门", systemName: "flame.fill", tint: Color(hex: 0xA15C00))
                            CapsuleMetric(text: "回复", systemName: "bubble.left.fill", tint: AtlassianTheme.teal)
                            CapsuleMetric(text: "iPad 分栏", systemName: "rectangle.split.2x1", tint: AtlassianTheme.blue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        loginField(title: "站点 URL", systemImage: "link") {
                            TextField("wiki.fit2cloud.com", text: $baseURL)
                                .textContentType(.URL)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .liquidField()
                        }

                        loginField(title: "用户名", systemImage: "person") {
                            TextField("username", text: $username)
                                .textContentType(.username)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .liquidField()
                        }

                        loginField(title: "密码", systemImage: "lock") {
                            SecureField("password", text: $password)
                                .textContentType(.password)
                                .textFieldStyle(.plain)
                                .liquidField()
                        }
                    }

                    if let errorMessage = sessionStore.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AtlassianTheme.red)
                    }

                    Button {
                        Task {
                            await sessionStore.signIn(baseURL: baseURL, username: username, password: password)
                        }
                    } label: {
                        if sessionStore.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("登录", systemImage: "arrow.right.circle.fill")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(sessionStore.isLoading)
                }
                .padding(24)
                .frame(maxWidth: 520, alignment: .leading)
                .liquidGlassPanel(cornerRadius: 34)
                .padding(20)
            }
            .background(LiquidBackground())
            .liquidNavigationChrome()
            .onAppear {
                if let configuration = sessionStore.configuration {
                    baseURL = configuration.baseURL.absoluteString
                    username = configuration.username
                }
            }
        }
    }

    private func loginField<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(appSettings.subheadlineFont)
                .foregroundStyle(AtlassianTheme.mutedText)
            content()
        }
    }
}

private enum MainTab: Hashable {
    case work
    case spaces
    case popular
    case search
    case settings
}

struct MainTabView: View {
    @State private var selectedTab: MainTab = .work
    @State private var refreshTokens: [MainTab: Int] = [:]

    var body: some View {
        TabView(selection: $selectedTab) {
            AdaptiveFeedView(kind: .recent, refreshToken: refreshTokens[.work, default: 0])
                .id(refreshTokens[.work, default: 0])
            .tabItem {
                Label("工作", systemImage: "rectangle.stack")
            }
            .tag(MainTab.work)

            NavigationStack {
                SpacesView(refreshToken: refreshTokens[.spaces, default: 0])
            }
            .id(refreshTokens[.spaces, default: 0])
            .tabItem {
                Label("空间", systemImage: "folder")
            }
            .tag(MainTab.spaces)

            AdaptiveFeedView(kind: .popular, refreshToken: refreshTokens[.popular, default: 0])
                .id(refreshTokens[.popular, default: 0])
            .tabItem {
                Label("热门", systemImage: "flame.fill")
            }
            .tag(MainTab.popular)

            NavigationStack {
                SearchView(refreshToken: refreshTokens[.search, default: 0])
            }
            .id(refreshTokens[.search, default: 0])
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .tag(MainTab.search)

            NavigationStack {
                SettingsView()
            }
            .id(refreshTokens[.settings, default: 0])
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
            .tag(MainTab.settings)
        }
        .tint(AtlassianTheme.blue)
        .liquidTabBarChrome()
        #if os(iOS)
        .background(
            TabBarTapObserver { index in
                if let tab = MainTab(index: index) {
                    refreshTokens[tab, default: 0] += 1
                }
            }
        )
        #endif
    }
}

private extension MainTab {
    init?(index: Int) {
        switch index {
        case 0: self = .work
        case 1: self = .spaces
        case 2: self = .popular
        case 3: self = .search
        case 4: self = .settings
        default: return nil
        }
    }
}

#if os(iOS)
private struct TabBarTapObserver: UIViewControllerRepresentable {
    let onTap: (Int) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            if let tabBarController = uiViewController.tabBarController,
               tabBarController.delegate !== context.coordinator {
                tabBarController.delegate = context.coordinator
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        let onTap: (Int) -> Void

        init(onTap: @escaping (Int) -> Void) {
            self.onTap = onTap
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            onTap(tabBarController.selectedIndex)
        }
    }
}
#endif
