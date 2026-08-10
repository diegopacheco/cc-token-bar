import Foundation
import Testing
@testable import cc_token_bar

@Test func decodesLiveSubscriptionWindows() throws {
    let data = Data("""
    {
      "five_hour": {"utilization": 37.5, "resets_at": "2026-08-08T18:30:00.000Z"},
      "seven_day": {"utilization": 62.25, "resets_at": "2026-08-10T00:00:00Z"}
    }
    """.utf8)

    let usage = try #require(ClaudeUsageClient.decode(data))

    #expect(usage.session?.utilization == 37.5)
    #expect(usage.weekly?.utilization == 62.25)
    #expect(usage.session?.resetAt != nil)
    #expect(usage.weekly?.resetAt != nil)
}

@Test func rejectsResponseWithoutSubscriptionWindows() {
    #expect(ClaudeUsageClient.decode(Data("{}".utf8)) == nil)
}

@Test func boundsUtilizationForSafeRendering() throws {
    let data = Data("""
    {
      "five_hour": {"utilization": -2},
      "seven_day": {"utilization": 104}
    }
    """.utf8)

    let usage = try #require(ClaudeUsageClient.decode(data))

    #expect(usage.session?.utilization == 0)
    #expect(usage.weekly?.utilization == 100)
}

@Test func decodesStoredOAuthCredential() {
    let data = Data("""
    {
      "claudeAiOauth": {"accessToken": "token", "refreshToken": "ignored"}
    }
    """.utf8)

    #expect(ClaudeUsageClient.decodeAccessToken(data) == "token")
    #expect(ClaudeUsageClient.decodeAccessToken(Data("{}".utf8)) == nil)
}

@Test func readsCurrentSessionAndAllModelsOnly() throws {
    let data = Data("""
    {
      "five_hour": {"utilization": 100, "resets_at": "2026-08-09T23:29:00Z"},
      "seven_day": {"utilization": 11, "resets_at": "2026-08-10T07:59:00Z"},
      "seven_day_opus": {"utilization": 99},
      "extra_usage": {"utilization": 125}
    }
    """.utf8)

    let usage = try #require(ClaudeUsageClient.decode(data))

    #expect(usage.session?.utilization == 100)
    #expect(usage.weekly?.utilization == 11)
}

@Test func persistsLiveSubscriptionUsage() throws {
    let expected = SubscriptionUsage(
        session: SubscriptionLimit(utilization: 100, resetAt: Date(timeIntervalSince1970: 1_786_316_940)),
        weekly: SubscriptionLimit(utilization: 11, resetAt: nil)
    )

    let data = try JSONEncoder().encode(expected)
    let actual = try JSONDecoder().decode(SubscriptionUsage.self, from: data)

    #expect(actual == expected)
}

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var seenTokens: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        Self.seenTokens.append(token)
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedClient(tokens: [String?]) -> ClaudeUsageClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    var remaining = tokens
    return ClaudeUsageClient(configuration: config, tokenLoader: {
        remaining.isEmpty ? nil : remaining.removeFirst()
    })
}

@Suite(.serialized)
struct TokenRotationTests {
    @Test func reloadsRotatedTokenAfterAuthFailure() async throws {
        let body = Data("""
        {"five_hour": {"utilization": 38}, "seven_day": {"utilization": 14}}
        """.utf8)
        StubURLProtocol.seenTokens = []
        StubURLProtocol.handler = { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer rotated" ? (200, body) : (401, Data())
        }
        let client = stubbedClient(tokens: ["stale", "rotated"])

        let result = await withCheckedContinuation { continuation in
            client.fetch { continuation.resume(returning: $0) }
        }

        guard case let .success(usage) = result else {
            Issue.record("expected success after token rotation, got \(result)")
            return
        }
        #expect(usage.session?.utilization == 38)
        #expect(StubURLProtocol.seenTokens == ["Bearer stale", "Bearer rotated"])
    }

    @Test func keepsLastKnownUsageWhenTokenIsRejectedAndUnchanged() async throws {
        StubURLProtocol.seenTokens = []
        StubURLProtocol.handler = { _ in (401, Data()) }
        let client = stubbedClient(tokens: ["stale", "stale"])

        let result = await withCheckedContinuation { continuation in
            client.fetch { continuation.resume(returning: $0) }
        }

        guard case .failed = result else {
            Issue.record("expected failed so cached usage survives, got \(result)")
            return
        }
        #expect(StubURLProtocol.seenTokens == ["Bearer stale"])
    }

    @Test func reportsUnavailableOnlyWhenCredentialsAreGone() async throws {
        StubURLProtocol.seenTokens = []
        StubURLProtocol.handler = { _ in (401, Data()) }
        let client = stubbedClient(tokens: ["stale"])

        let result = await withCheckedContinuation { continuation in
            client.fetch { continuation.resume(returning: $0) }
        }

        guard case .unavailable = result else {
            Issue.record("expected unavailable when no credential remains, got \(result)")
            return
        }
    }
}
