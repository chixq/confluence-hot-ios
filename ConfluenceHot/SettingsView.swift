import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSaving = false
    @State private var isLoadingSystemInfo = false
    @State private var notificationStatusText: String?
    @State private var systemInfo: AdminSystemInfo?
    @State private var systemInfoError: String?

    var body: some View {
        ScrollView {
            SectionHeader(title: "设置", subtitle: sessionStore.user?.displayName)

            VStack(spacing: 16) {
                settingsCard(title: "账号") {
                    VStack(alignment: .leading, spacing: 12) {
                        inputField(title: "站点 URL", systemImage: "link") {
                            TextField("wiki.fit2cloud.com", text: $baseURL)
                                .textContentType(.URL)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .liquidField()
                        }

                        inputField(title: "用户名", systemImage: "person") {
                            TextField("username", text: $username)
                                .textContentType(.username)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .liquidField()
                        }

                        inputField(title: "密码", systemImage: "lock") {
                            SecureField("留空则不修改", text: $password)
                                .textContentType(.password)
                                .textFieldStyle(.plain)
                                .liquidField()
                        }
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
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("夜间模式", systemImage: "moon")
                                .font(appSettings.subheadlineFont)
                                .foregroundStyle(AtlassianTheme.mutedText)
                            Picker("夜间模式", selection: Binding(
                                get: { appSettings.appearanceMode },
                                set: { appSettings.appearanceMode = $0 }
                            )) {
                                ForEach(AppearanceMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Label("字体", systemImage: "textformat")
                                .font(appSettings.subheadlineFont)
                                .foregroundStyle(AtlassianTheme.mutedText)
                            Picker("字体", selection: Binding(
                                get: { appSettings.fontChoice },
                                set: { appSettings.fontChoice = $0 }
                            )) {
                                ForEach(InterfaceFontChoice.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("字号", systemImage: "textformat.size")
                                Spacer()
                                Text("\(Int(appSettings.fontScale * 100))%")
                                    .foregroundStyle(AtlassianTheme.mutedText)
                            }
                            .font(appSettings.subheadlineFont)
                            Slider(value: $appSettings.fontScale, in: 0.85...1.25, step: 0.05)
                        }

                        Toggle(isOn: $appSettings.landscapeSplitEnabled) {
                            Label("横屏分栏阅读", systemImage: "rectangle.split.2x1")
                        }
                    }
                }

                settingsCard(title: "热门推送") {
                    VStack(alignment: .leading, spacing: 12) {
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
                                .foregroundStyle(AtlassianTheme.blue)
                        }
                    }
                }

                settingsCard(title: "管理员") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("管理员可点击读取当前站点的系统信息和统计概览。数据不会缓存，每次点击都会重新请求。")
                            .font(appSettings.subheadlineFont)
                            .foregroundStyle(AtlassianTheme.mutedText)

                        Button {
                            Task { await loadSystemInfo() }
                        } label: {
                            if isLoadingSystemInfo {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label("读取系统信息", systemImage: "server.rack")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isLoadingSystemInfo)

                        if let systemInfoError {
                            Text(systemInfoError)
                                .font(appSettings.subheadlineFont)
                                .foregroundStyle(AtlassianTheme.red)
                        }

                        if let systemInfo {
                            AdminSystemInfoView(info: systemInfo)
                        }
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
                .font(appSettings.fontChoice.font(size: 13 * appSettings.fontScale, relativeTo: .caption).weight(.semibold))
                .foregroundStyle(AtlassianTheme.mutedText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .liquidGlassPanel(cornerRadius: 28)
        }
    }

    private func inputField<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(appSettings.subheadlineFont)
                .foregroundStyle(AtlassianTheme.mutedText)
            content()
        }
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

    private func loadSystemInfo() async {
        guard let client = sessionStore.client else { return }
        isLoadingSystemInfo = true
        systemInfoError = nil
        do {
            systemInfo = try await client.fetchAdminSystemInfo()
        } catch {
            systemInfoError = "读取失败：\(error.localizedDescription)"
        }
        isLoadingSystemInfo = false
    }
}

struct AdminSystemInfoView: View {
    @EnvironmentObject private var appSettings: AppSettings

    let info: AdminSystemInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("生成时间：\(info.generatedAt.formatted(date: .abbreviated, time: .standard))")
                .font(appSettings.subheadlineFont)
                .foregroundStyle(AtlassianTheme.mutedText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("用户", value: info.userCount)
                metric("页面", value: info.pageCount)
                metric("博客", value: info.blogPostCount)
                metric("登录审计", value: info.loginAuditCount)
            }

            if !info.rawSystemInfo.isEmpty {
                Divider()
                ForEach(info.rawSystemInfo.keys.sorted().prefix(12), id: \.self) { key in
                    HStack(alignment: .top) {
                        Text(key)
                            .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                            .foregroundStyle(AtlassianTheme.mutedText)
                            .frame(width: 130, alignment: .leading)
                        Text(info.rawSystemInfo[key] ?? "")
                            .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                            .foregroundStyle(AtlassianTheme.text)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private func metric(_ title: String, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(appSettings.fontChoice.font(size: 12 * appSettings.fontScale, relativeTo: .caption))
                .foregroundStyle(AtlassianTheme.mutedText)
            Text(value.map(String.init) ?? "不可用")
                .font(appSettings.headlineFont)
                .foregroundStyle(AtlassianTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AtlassianTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
