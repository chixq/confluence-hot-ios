import Foundation

private enum SessionDefaultsKeys {
    static let baseURL = "server.baseURL"
    static let username = "server.username"
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var configuration: ServerConfiguration?
    @Published private(set) var user: UserProfile?
    @Published private(set) var client: ConfluenceClient?
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard

    var isSignedIn: Bool {
        client != nil && user != nil
    }

    func bootstrap() async {
        defer { isLoading = false }
        guard let storedConfiguration = loadConfiguration(),
              let password = KeychainStore.password(account: storedConfiguration.keychainAccount) else {
            configuration = loadConfiguration()
            return
        }

        await establishSession(configuration: storedConfiguration, password: password, persist: false)
    }

    func signIn(baseURL: String, username: String, password: String) async {
        guard !password.isEmpty else {
            errorMessage = ConfluenceClientError.missingPassword.localizedDescription
            return
        }

        do {
            let configuration = try ServerConfiguration.normalized(baseURL: baseURL, username: username)
            await establishSession(configuration: configuration, password: password, persist: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateConnection(baseURL: String, username: String, password: String?) async {
        do {
            let updatedConfiguration = try ServerConfiguration.normalized(baseURL: baseURL, username: username)
            let resolvedPassword: String

            if let password, !password.isEmpty {
                resolvedPassword = password
            } else if let currentPassword = KeychainStore.password(account: updatedConfiguration.keychainAccount) {
                resolvedPassword = currentPassword
            } else if let oldConfiguration = configuration,
                      let currentPassword = KeychainStore.password(account: oldConfiguration.keychainAccount) {
                resolvedPassword = currentPassword
            } else {
                throw ConfluenceClientError.missingPassword
            }

            await establishSession(configuration: updatedConfiguration, password: resolvedPassword, persist: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        if let configuration {
            try? KeychainStore.deletePassword(account: configuration.keychainAccount)
        }

        defaults.removeObject(forKey: SessionDefaultsKeys.baseURL)
        defaults.removeObject(forKey: SessionDefaultsKeys.username)
        configuration = nil
        user = nil
        client = nil
        errorMessage = nil
    }

    private func establishSession(configuration: ServerConfiguration, password: String, persist: Bool) async {
        isLoading = true
        errorMessage = nil

        let client = ConfluenceClient(configuration: configuration, password: password)

        do {
            let user = try await client.validateSession()
            if persist {
                defaults.set(configuration.baseURL.absoluteString, forKey: SessionDefaultsKeys.baseURL)
                defaults.set(configuration.username, forKey: SessionDefaultsKeys.username)
                try KeychainStore.savePassword(password, account: configuration.keychainAccount)
            }

            self.configuration = configuration
            self.client = client
            self.user = user
        } catch {
            self.client = nil
            self.user = nil
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadConfiguration() -> ServerConfiguration? {
        Self.loadStoredConfiguration(defaults: defaults)
    }

    nonisolated static func loadStoredConfiguration(defaults: UserDefaults = .standard) -> ServerConfiguration? {
        guard let baseURL = defaults.string(forKey: SessionDefaultsKeys.baseURL),
              let username = defaults.string(forKey: SessionDefaultsKeys.username) else {
            return nil
        }
        return try? ServerConfiguration.normalized(baseURL: baseURL, username: username)
    }
}
