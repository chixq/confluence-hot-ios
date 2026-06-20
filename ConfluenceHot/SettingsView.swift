import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            SectionHeader(title: "设置", subtitle: sessionStore.user?.displayName)

            VStack(alignment: .leading, spacing: 18) {
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
                        .font(.footnote)
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

                Button {
                    sessionStore.signOut()
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
            .background(AtlassianTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AtlassianTheme.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
        .background(AtlassianTheme.background)
        .inlineNavigationTitle()
        .onAppear {
            if let configuration = sessionStore.configuration {
                baseURL = configuration.baseURL.absoluteString
                username = configuration.username
            }
        }
    }

    private func save() async {
        isSaving = true
        await sessionStore.updateConnection(
            baseURL: baseURL,
            username: username,
            password: password.isEmpty ? nil : password
        )
        password = ""
        isSaving = false
    }
}
