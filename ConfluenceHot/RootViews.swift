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
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(AtlassianTheme.blue)
                        Text("Confluence")
                            .font(appSettings.fontChoice == .system ? .largeTitle.weight(.bold) : appSettings.fontChoice.font(size: 34 * appSettings.fontScale, relativeTo: .largeTitle))
                            .foregroundStyle(AtlassianTheme.text)
                        Text("连接 Server 或 Data Center 站点")
                            .font(appSettings.subheadlineFont)
                            .foregroundStyle(AtlassianTheme.mutedText)
                    }

                    VStack(spacing: 14) {
                        TextField("站点 URL", text: $baseURL)
                            .textContentType(.URL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        TextField("用户名", text: $username)
                            .textContentType(.username)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        SecureField("密码", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
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
            }
            .background(AtlassianTheme.background)
            .onAppear {
                if let configuration = sessionStore.configuration {
                    baseURL = configuration.baseURL.absoluteString
                    username = configuration.username
                }
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            AdaptiveFeedView(kind: .recent)
            .tabItem {
                Label("最新", systemImage: "clock")
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
    }
}
