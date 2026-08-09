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
