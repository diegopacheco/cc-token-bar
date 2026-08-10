import Foundation
import Security

final class ClaudeUsageClient {
    enum FetchResult {
        case success(SubscriptionUsage)
        case rateLimited(Date)
        case unavailable
        case failed
    }

    private struct Credentials: Decodable {
        let claudeAiOauth: OAuth?
    }

    private struct OAuth: Decodable {
        let accessToken: String?
    }

    private struct Response: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    private struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    private let queue = DispatchQueue(label: "cc-token-bar.subscription", qos: .userInitiated)
    private let session: URLSession
    private let tokenLoader: (() -> String?)?
    private var accessToken: String?
    private var isFetching = false
    private var nextFetchAt = Date.distantPast

    convenience init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 3
        self.init(configuration: config, tokenLoader: nil)
    }

    init(configuration: URLSessionConfiguration, tokenLoader: (() -> String?)?) {
        self.session = URLSession(configuration: configuration)
        self.tokenLoader = tokenLoader
    }

    private func currentToken() -> String? {
        if let loader = tokenLoader { return loader() }
        return loadAccessToken()
    }

    func fetch(completion: @escaping (FetchResult) -> Void) {
        queue.async { [weak self] in
            guard let self = self, !self.isFetching, Date() >= self.nextFetchAt else { return }
            self.isFetching = true
            self.nextFetchAt = Date().addingTimeInterval(60)
            self.send(reloadTokenOnAuthFailure: true, completion: completion)
        }
    }

    private func send(reloadTokenOnAuthFailure: Bool, completion: @escaping (FetchResult) -> Void) {
        guard let token = accessToken ?? currentToken() else {
            isFetching = false
            completion(.unavailable)
            return
        }
        accessToken = token
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 2.5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("claude-code/2.1", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, error in
            self?.queue.async {
                guard let self = self else { return }
                guard error == nil,
                      let http = response as? HTTPURLResponse else {
                    self.isFetching = false
                    completion(.failed)
                    return
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    self.accessToken = nil
                    if reloadTokenOnAuthFailure {
                        guard let refreshed = self.currentToken() else {
                            self.isFetching = false
                            completion(.unavailable)
                            return
                        }
                        if refreshed != token {
                            self.accessToken = refreshed
                            self.send(reloadTokenOnAuthFailure: false, completion: completion)
                            return
                        }
                    }
                    self.isFetching = false
                    completion(.failed)
                    return
                }
                if http.statusCode == 429 {
                    let resetAt = Date().addingTimeInterval(Self.retryDelay(from: http))
                    self.nextFetchAt = resetAt
                    self.isFetching = false
                    completion(.rateLimited(resetAt))
                    return
                }
                guard (200..<300).contains(http.statusCode),
                      let data = data,
                      let usage = Self.decode(data) else {
                    self.isFetching = false
                    completion(.failed)
                    return
                }
                self.isFetching = false
                completion(.success(usage))
            }
        }.resume()
    }

    static func decode(_ data: Data) -> SubscriptionUsage? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let session = response.fiveHour.flatMap(limit)
        let weekly = response.sevenDay.flatMap(limit)
        guard session != nil || weekly != nil else { return nil }
        return SubscriptionUsage(session: session, weekly: weekly)
    }

    private static func limit(_ window: Window) -> SubscriptionLimit? {
        guard let utilization = window.utilization else { return nil }
        return SubscriptionLimit(
            utilization: min(100, max(0, utilization)),
            resetAt: window.resetsAt.flatMap(parseDate)
        )
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso = ISO8601DateFormatter()

    private static func parseDate(_ value: String) -> Date? {
        isoFractional.date(from: value) ?? iso.date(from: value)
    }

    private func loadAccessToken() -> String? {
        if let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"], !token.isEmpty {
            return token
        }
        if let data = keychainCredentials(), let token = Self.decodeAccessToken(data) {
            return token
        }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.decodeAccessToken(data)
    }

    private func keychainCredentials() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func decodeAccessToken(_ data: Data) -> String? {
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              let token = credentials.claudeAiOauth?.accessToken,
              !token.isEmpty else { return nil }
        return token
    }

    private static func retryDelay(from response: HTTPURLResponse) -> TimeInterval {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value) else { return 60 }
        return max(60, seconds)
    }
}
