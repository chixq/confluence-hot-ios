import SwiftUI

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

struct MainTabView: View {
    var body: some View {
        TabView {
            AdaptiveFeedView(kind: .recent)
            .tabItem {
                Label("工作", systemImage: "rectangle.stack")
            }

            NavigationStack {
                SpacesView()
            }
            .tabItem {
                Label("空间", systemImage: "folder")
            }

            AdaptiveFeedView(kind: .popular)
            .tabItem {
                Label("热门", systemImage: "flame.fill")
            }

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .tint(AtlassianTheme.blue)
        .liquidTabBarChrome()
    }
}
