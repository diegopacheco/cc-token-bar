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
