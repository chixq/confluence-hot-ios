import SwiftUI

@main
struct ConfluenceHotApp: App {
    @StateObject private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .task {
                    await sessionStore.bootstrap()
                }
        }
    }
}
