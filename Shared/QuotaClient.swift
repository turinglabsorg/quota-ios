import Foundation
import Security

/// Talks to quota-server: pairing and usage. The device token lives in the Keychain and the last payload in
/// the App Group container, both shared with the widgets.
enum QuotaClient {
    /// From `QUOTA_APP_GROUP` in project.yml, through the `QuotaAppGroup` Info.plist key.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "QuotaAppGroup") as? String ?? "group.com.turinglabs.quota"

    enum Failure: LocalizedError, Equatable {
        case notPaired
        case invalidCode
        case expiredCode
        case unauthorized
        case server(Int)
        case network
        case invalidResponse
        case keychain

        var errorDescription: String? {
            switch self {
            case .notPaired: String(localized: "Pair this device with your Quota server.")
            case .invalidCode: String(localized: "That pairing code is not valid.")
            case .expiredCode: String(localized: "That pairing code expired. Create a new one.")
            case .unauthorized: String(localized: "This device is no longer paired. Pair it again.")
            case .server(let status): String(localized: "Server error (HTTP \(status)).")
            case .network: String(localized: "Can't reach the Quota server.")
            case .invalidResponse: String(localized: "Unrecognized response.")
            case .keychain: String(localized: "Couldn't save the pairing on this device.")
            }
        }
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var serverURL: URL? {
        get { defaults.string(forKey: "serverURL").flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: "serverURL") }
    }

    /// Set when the app runs with `-QuotaSampleData`: app and widgets show sample accounts (for screenshots).
    static var showsSampleData: Bool {
        get { defaults.bool(forKey: "sampleData") }
        set { defaults.set(newValue, forKey: "sampleData") }
    }

    static var isPaired: Bool {
        serverURL != nil && TokenStore.read() != nil
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static func pair(server: URL, code: String, deviceName: String) async throws {
        var request = URLRequest(url: server.appendingPathComponent("v1/pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let digits = code.filter(\.isNumber)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": digits, "name": deviceName])
        let (data, status) = try await send(request)
        switch status {
        case 200:
            guard let token = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["token"], !token.isEmpty else {
                throw Failure.invalidResponse
            }
            guard TokenStore.save(token) else { throw Failure.keychain }
            serverURL = server
            removeCache()
        case 401: throw Failure.invalidCode
        case 410: throw Failure.expiredCode
        default: throw Failure.server(status)
        }
    }

    static func fetchUsage() async throws -> UsagePayload {
        guard let server = serverURL, let token = TokenStore.read() else { throw Failure.notPaired }
        var request = URLRequest(url: server.appendingPathComponent("v1/usage"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, status) = try await send(request)
        switch status {
        case 200:
            guard let payload = try? UsagePayload.decode(data) else { throw Failure.invalidResponse }
            try? data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return payload
        case 401: throw Failure.unauthorized
        default: throw Failure.server(status)
        }
    }

    static func cachedUsage() -> UsagePayload? {
        (try? Data(contentsOf: cacheURL)).flatMap { try? UsagePayload.decode($0) }
    }

    static func unpair() {
        TokenStore.delete()
        removeCache()
    }

    private static var cacheURL: URL {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.temporaryDirectory
        return container.appendingPathComponent("usage.json")
    }

    private static func removeCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw Failure.network
        }
    }
}

/// The device token in the Keychain, readable by the widgets through the App Group after the first unlock.
enum TokenStore {
    private static let service = "com.turinglabs.quota.server"
    private static let account = "device-token"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: QuotaClient.appGroup,
        ]
    }

    static func read() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
