import Foundation
import UserNotifications

#if os(iOS)
import BackgroundTasks
#endif

enum PopularNotificationManager {
    static let backgroundTaskIdentifier = "com.chixiaoqiang.confluencehot.popular-refresh"
    private static let seenIDsKey = "notifications.popular.seenIDs"

    static func configure() {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: task)
        }
        #endif
    }

    @MainActor
    static func updateSchedule(settings: AppSettings, client: ConfluenceClient?) async {
        guard settings.notificationFrequency != .off else {
            #if os(iOS)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
            #endif
            return
        }

        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return }

        if let client {
            await markCurrentPopularAsSeenIfNeeded(client: client)
        }
        scheduleNextRefresh(frequency: settings.notificationFrequency)
    }

    static func scheduleNextRefresh(frequency: PopularNotificationFrequency) {
        #if os(iOS)
        guard let interval = frequency.interval else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    static func checkForNewPopular(client: ConfluenceClient, frequency: PopularNotificationFrequency) async {
        guard frequency != .off else { return }

        do {
            let items = try await client.fetchPopular(limit: 10)
            let seenIDs = Set(UserDefaults.standard.stringArray(forKey: seenIDsKey) ?? [])
            let newItems = items.filter { !seenIDs.contains($0.id) }

            if let item = newItems.first {
                await deliverNotification(for: item)
            }

            let merged = Array(Set(items.map(\.id)).union(seenIDs)).prefix(100)
            UserDefaults.standard.set(Array(merged), forKey: seenIDsKey)
        } catch {
            // Background refresh is opportunistic; keep the next attempt quiet.
        }
    }

    @MainActor
    private static func markCurrentPopularAsSeenIfNeeded(client: ConfluenceClient) async {
        let existing = UserDefaults.standard.stringArray(forKey: seenIDsKey) ?? []
        guard existing.isEmpty else { return }

        do {
            let items = try await client.fetchPopular(limit: 20)
            UserDefaults.standard.set(items.map(\.id), forKey: seenIDsKey)
        } catch {
            // Permission or network errors are surfaced by the normal app views.
        }
    }

    private static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    private static func deliverNotification(for item: ContentItem) async {
        let content = UNMutableNotificationContent()
        content.title = "新的热门内容"
        content.body = item.title
        content.sound = .default
        content.userInfo = ["contentID": item.id]

        let request = UNNotificationRequest(
            identifier: "popular-\(item.id)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    #if os(iOS)
    private static func handle(task: BGAppRefreshTask) {
        let defaults = UserDefaults.standard
        let frequency = PopularNotificationFrequency(rawValue: defaults.string(forKey: "notifications.popular.frequency") ?? "") ?? .off

        scheduleNextRefresh(frequency: frequency)

        let operation = Task {
            guard let configuration = SessionStore.loadStoredConfiguration(),
                  let password = KeychainStore.password(account: configuration.keychainAccount),
                  frequency != .off else {
                task.setTaskCompleted(success: false)
                return
            }

            let client = ConfluenceClient(configuration: configuration, password: password)
            await checkForNewPopular(client: client, frequency: frequency)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            operation.cancel()
        }
    }
    #endif
}
