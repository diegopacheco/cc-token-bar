import Foundation

final class ClaudeUsageClient {
    enum FetchResult {
        case success(SubscriptionUsage)
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
    private var accessToken: String?
    private var isFetching = false

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 3
        session = URLSession(configuration: config)
    }

    func fetch(completion: @escaping (FetchResult) -> Void) {
        queue.async { [weak self] in
            guard let self = self, !self.isFetching else { return }
            self.isFetching = true
            guard let token = self.accessToken ?? self.loadAccessToken() else {
                self.isFetching = false
                completion(.unavailable)
                return
            }
            self.accessToken = token
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.timeoutInterval = 2.5
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("claude-code/2.1", forHTTPHeaderField: "User-Agent")
            self.session.dataTask(with: request) { [weak self] data, response, error in
                self?.queue.async {
                    guard let self = self else { return }
                    self.isFetching = false
                    guard error == nil,
                          let http = response as? HTTPURLResponse else {
                        completion(.failed)
                        return
                    }
                    if http.statusCode == 401 || http.statusCode == 403 {
                        self.accessToken = nil
                        completion(.unavailable)
                        return
                    }
                    guard (200..<300).contains(http.statusCode),
                          let data = data,
                          let usage = Self.decode(data) else {
                        completion(.failed)
                        return
                    }
                    completion(.success(usage))
                }
            }.resume()
        }
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
        if let data = keychainCredentials(), let token = decodeToken(data) {
            return token
        }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeToken(data)
    }

    private func keychainCredentials() -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        guard (try? process.run()) != nil else { return nil }
        guard finished.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private func decodeToken(_ data: Data) -> String? {
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              let token = credentials.claudeAiOauth?.accessToken,
              !token.isEmpty else { return nil }
        return token
    }
}
