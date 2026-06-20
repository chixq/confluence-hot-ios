import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSaving = false
    @State private var notificationStatusText: String?

    var body: some View {
        ScrollView {
            SectionHeader(title: "设置", subtitle: sessionStore.user?.displayName)

            VStack(spacing: 16) {
                settingsCard(title: "账号") {
                    VStack(spacing: 14) {
                        TextField("站点 URL", text: $baseURL)
                            .textContentType(.URL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        TextField("用户名", text: $username)
                            .textContentType(.username)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        SecureField("新密码", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let errorMessage = sessionStore.errorMessage {
                        Text(errorMessage)
                            .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .footnote))
                            .foregroundStyle(AtlassianTheme.red)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("保存", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving)
                }

                settingsCard(title: "显示") {
                    Picker("夜间模式", selection: Binding(
                        get: { appSettings.appearanceMode },
                        set: { appSettings.appearanceMode = $0 }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("字体", selection: Binding(
                        get: { appSettings.fontChoice },
                        set: { appSettings.fontChoice = $0 }
                    )) {
                        ForEach(InterfaceFontChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("字号")
                            Spacer()
                            Text("\(Int(appSettings.fontScale * 100))%")
                                .foregroundStyle(AtlassianTheme.mutedText)
                        }
                        Slider(value: $appSettings.fontScale, in: 0.85...1.25, step: 0.05)
                    }

                    Toggle("横屏分栏阅读", isOn: $appSettings.landscapeSplitEnabled)
                }

                settingsCard(title: "热门推送") {
                    Picker("检查频率", selection: Binding(
                        get: { appSettings.notificationFrequency },
                        set: { frequency in
                            appSettings.notificationFrequency = frequency
                            Task { await updateNotifications() }
                        }
                    )) {
                        ForEach(PopularNotificationFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("开启后会在系统允许的后台刷新窗口内检查热门内容，只推送之前没有提醒过的新热门。iOS 会按电量、网络和使用习惯调整实际执行时间。")
                        .font(appSettings.subheadlineFont)
                        .foregroundStyle(AtlassianTheme.mutedText)

                    if let notificationStatusText {
                        Text(notificationStatusText)
                            .font(appSettings.subheadlineFont)
                            .foregroundStyle(AtlassianTheme.mutedText)
                    }
                }

                settingsCard(title: "会话") {
                    Button {
                        sessionStore.signOut()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(LiquidBackground())
        .inlineNavigationTitle()
        .liquidNavigationChrome()
        .onAppear {
            if let configuration = sessionStore.configuration {
                baseURL = configuration.baseURL.absoluteString
                username = configuration.username
            }
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(appSettings.headlineFont)
                .foregroundStyle(AtlassianTheme.text)
            content()
        }
        .padding(16)
        .liquidGlassPanel(cornerRadius: 26)
    }

    private func save() async {
        isSaving = true
        await sessionStore.updateConnection(
            baseURL: baseURL,
            username: username,
            password: password.isEmpty ? nil : password
        )
        await PopularNotificationManager.updateSchedule(settings: appSettings, client: sessionStore.client)
        password = ""
        isSaving = false
    }

    private func updateNotifications() async {
        await PopularNotificationManager.updateSchedule(settings: appSettings, client: sessionStore.client)
        switch appSettings.notificationFrequency {
        case .off:
            notificationStatusText = "热门推送已关闭"
        case .daily:
            notificationStatusText = "已安排每天检查新的热门内容"
        case .weekly:
            notificationStatusText = "已安排每周检查新的热门内容"
        }
    }
}
