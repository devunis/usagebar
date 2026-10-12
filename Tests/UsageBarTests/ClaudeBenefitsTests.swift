import XCTest
@testable import UsageBar

final class ClaudeBenefitsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCloudCreditsPreserveDollarUnitsAndPreferReportedBalance() throws {
        let credits = try XCTUnwrap(ClaudeOAuthUsageProvider.parseCloudCredits([
            "limit_dollars": 250, "used_dollars": 100, "remaining_dollars": 200,
            "resets_at": "2026-11-04T19:59:00Z"
        ]))
        XCTAssertEqual(credits.allowanceUSD, 250)
        XCTAssertEqual(credits.remainingUSD, 200)
        XCTAssertEqual(credits.usedPercent, 20, accuracy: 0.0001)
        XCTAssertNotNil(credits.expiresAt)
    }

    func testCloudCreditFallbackZeroBalanceAndExpiry() throws {
        let credits = try XCTUnwrap(ClaudeOAuthUsageProvider.parseCloudCredits([
            "limit_dollars": 250, "used_dollars": 250,
            "resets_at": now.timeIntervalSince1970
        ]))
        XCTAssertEqual(credits.remainingUSD, 0)
        XCTAssertEqual(credits.usedPercent, 100)
        XCTAssertTrue(credits.isExpired(at: now))
        XCTAssertNil(ClaudeOAuthUsageProvider.parseCloudCredits(["limit_dollars": 250]))
        XCTAssertNil(ClaudeOAuthUsageProvider.parseCloudCredits(["limit_dollars": true, "remaining_dollars": 1]))
    }

    func testResetInventoryExcludesPausedFutureAndExpiredGrants() throws {
        func grant(_ left: Int, start: Double, end: Double, paused: Bool = false) -> [String: Any] {
            ["resets_total": 2, "resets_left": left, "paused": paused,
             "starts_at": now.timeIntervalSince1970 + start,
             "ends_at": now.timeIntervalSince1970 + end]
        }
        let inventory = try XCTUnwrap(ClaudeOAuthUsageProvider.parseResets([
            "eligible": true,
            "grants": [grant(2, start: -10, end: 10), grant(1, start: -10, end: 100, paused: true),
                       grant(1, start: 10, end: 100), grant(1, start: -100, end: 0)]
        ]))
        XCTAssertEqual(inventory.availableCount(at: now), 2)
        XCTAssertEqual(inventory.nextExpiration(at: now), now.addingTimeInterval(10))
        XCTAssertEqual(inventory.availableCount(at: now.addingTimeInterval(100)), 0)
    }

    func testUnknownResetInventoryIsNotZeroAvailable() throws {
        XCTAssertNil(ClaudeOAuthUsageProvider.parseResets(nil))
        XCTAssertNil(ClaudeOAuthUsageProvider.parseResets(["eligible": false, "grants": []]))
        XCTAssertNil(ClaudeOAuthUsageProvider.parseResets(["eligible": true, "grants": [["resets_left": 1]]]))
        let inventory = try XCTUnwrap(ClaudeOAuthUsageProvider.parseResets(["eligible": true, "grants": []]))
        XCTAssertEqual(inventory.availableCount(at: now), 0)
    }

    func testMalformedBenefitsDoNotDiscardMeasuredQuotaWindows() throws {
        let snapshot = try ClaudeOAuthUsageProvider.parse([
            "five_hour": ["utilization": 14], "seven_day": ["utilization": 2],
            "seven_day_fable": ["utilization": 2],
            "iguana_necktie": ["limit_dollars": "invalid"], "cedar_ember": NSNull()
        ], now: now)
        XCTAssertEqual(snapshot.windows.map(\.title), ["5시간", "주간", "Fable 주간"])
        XCTAssertNil(snapshot.claudeBenefits?.cloudCredits)
        XCTAssertNil(snapshot.claudeBenefits?.resets)
    }

    func testLiveClaudeBenefitsWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["USAGEBAR_LIVE_CLAUDE_BENEFITS_TEST"] == "1" else {
            throw XCTSkip("명시적으로 요청할 때만 기존 Claude 로그인으로 추가 정보를 조회합니다.")
        }
        guard let token = ClaudeOAuthUsageProvider.accessTokenWithoutPrompt() else {
            throw XCTSkip("인증창 없이 읽을 수 있는 Claude 로그인 정보가 없습니다.")
        }
        let snapshot = try await ClaudeOAuthUsageProvider.fetchQuota(accessToken: token)
        XCTAssertFalse(snapshot.windows.isEmpty)
        // Print only non-sensitive quota/benefit summaries, never tokens or raw responses.
        print("Claude benefits: cloud=\(snapshot.claudeBenefits?.cloudCredits?.remainingUSD.description ?? "unavailable"), resets=\(snapshot.claudeBenefits?.resets?.availableCount(at: Date()).description ?? "unavailable")")
    }
}
