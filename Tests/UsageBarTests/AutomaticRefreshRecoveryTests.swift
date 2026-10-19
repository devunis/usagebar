import XCTest
@testable import UsageBar

final class AutomaticRefreshRecoveryTests: XCTestCase {
    func testThreeDayOldDataAndRecentFailedRefreshAreRetried() throws {
        let now = Date()
        let old = try ClaudeOAuthUsageProvider.parse(["five_hour": ["utilization": 10]],
                                                    now: now.addingTimeInterval(-3 * 24 * 60 * 60))
        let fresh = try ClaudeOAuthUsageProvider.parse(["five_hour": ["utilization": 10]], now: now)
        XCTAssertTrue(shouldRefreshAfterResume(state: .loaded(old), hasFailure: false, now: now))
        XCTAssertTrue(shouldRefreshAfterResume(state: .loaded(fresh), hasFailure: true, now: now))
        XCTAssertFalse(shouldRefreshAfterResume(state: .loaded(fresh), hasFailure: false, now: now))
        XCTAssertTrue(shouldRefreshAfterResume(state: .failed("offline"), hasFailure: true, now: now))
    }

    @MainActor
    func testWakeSessionAndOnlineEventsCoalesceIntoOneRefresh() async throws {
        var count = 0
        let recovery = AutomaticRefreshRecovery(delay: .milliseconds(10), observeSystemEvents: false,
                                                isEnabled: { true }, refresh: { count += 1 })
        recovery.schedule()
        recovery.schedule()
        recovery.schedule()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testManualModePreventsWakeRefreshAndPendingRefresh() async throws {
        var enabled = false
        var count = 0
        let recovery = AutomaticRefreshRecovery(delay: .milliseconds(10), observeSystemEvents: false,
                                                isEnabled: { enabled }, refresh: { count += 1 })
        recovery.schedule()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(count, 0)
        enabled = true
        recovery.schedule()
        enabled = false
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testWakeFailuresRetryTwiceThenReturnToRegularTimer() async throws {
        var count = 0
        var recovery: AutomaticRefreshRecovery?
        recovery = AutomaticRefreshRecovery(delay: .milliseconds(5), retryDelay: .milliseconds(5),
            observeSystemEvents: false, isEnabled: { true }, refresh: {
                count += 1
                recovery?.retryAfterFailure()
                recovery?.retryAfterFailure() // Concurrent provider failures must coalesce.
            })
        recovery?.schedule()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(count, 3)
        recovery = nil
    }
}
