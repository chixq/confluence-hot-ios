import SwiftUI

@main
struct ConfluenceHotApp: App {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var appSettings = AppSettings()

    init() {
        PopularNotificationManager.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .environmentObject(appSettings)
                .preferredColorScheme(appSettings.preferredColorScheme)
                .environment(\.font, appSettings.baseFont)
                .task {
                    await sessionStore.bootstrap()
                    await PopularNotificationManager.updateSchedule(settings: appSettings, client: sessionStore.client)
                }
        }
    }
}
