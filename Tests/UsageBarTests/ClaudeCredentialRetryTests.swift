import XCTest
@testable import UsageBar

final class ClaudeCredentialRetryTests: XCTestCase {
    func testBackgroundReadDisablesLegacyDialogsAndRestoresPolicy() {
        var policy = true
        var changes: [Bool] = []
        let result: String? = ClaudeKeychainAccess.withInteractionPolicy(
            allowAuthenticationUI: false,
            getPolicy: { policy },
            setPolicy: { policy = $0; changes.append($0); return true },
            operation: {
                XCTAssertFalse(policy)
                return "fixture"
            }
        )
        XCTAssertEqual(result, "fixture")
        XCTAssertEqual(changes, [false, true])
        XCTAssertTrue(policy)
    }

    func testOnlyExplicitActionEnablesDialogsAndRestoresPriorDisabledPolicy() {
        var policy = false
        let result: String? = ClaudeKeychainAccess.withInteractionPolicy(
            allowAuthenticationUI: true,
            getPolicy: { policy },
            setPolicy: { policy = $0; return true },
            operation: { XCTAssertTrue(policy); return "fixture" }
        )
        XCTAssertNotNil(result)
        XCTAssertFalse(policy)
    }

    func testDeniedReadRestoresPolicyAndDoesNotDisableFutureRetries() {
        var policy = true
        var attempts = 0
        for _ in 0..<2 {
            let result: String? = ClaudeKeychainAccess.withInteractionPolicy(
                allowAuthenticationUI: false,
                getPolicy: { policy },
                setPolicy: { policy = $0; return true },
                operation: { attempts += 1; XCTAssertFalse(policy); return nil }
            )
            XCTAssertNil(result)
            XCTAssertTrue(policy)
        }
        XCTAssertEqual(attempts, 2)
    }

    func testFailedPolicySetupNeverReadsCredential() {
        var operations = 0
        let unknown: String? = ClaudeKeychainAccess.withInteractionPolicy(
            allowAuthenticationUI: false, getPolicy: { nil },
            setPolicy: { _ in XCTFail("Must not change an unknown policy"); return false },
            operation: { operations += 1; return "fixture" }
        )
        let rejected: String? = ClaudeKeychainAccess.withInteractionPolicy(
            allowAuthenticationUI: false, getPolicy: { true }, setPolicy: { _ in false },
            operation: { operations += 1; return "fixture" }
        )
        XCTAssertNil(unknown)
        XCTAssertNil(rejected)
        XCTAssertEqual(operations, 0)
    }

    func testCredentialDenialIsRetriedAndCanRecoverWithoutCLI() async throws {
        let probe = RetryProbe(denyFirstRead: true, failFirstRequest: false)
        let provider = ClaudeQuotaProvider(
            loadCLI: { throw UsageProviderError.unsupported("fixture: CLI unavailable") },
            readToken: { await probe.read() },
            loadQuota: { try await probe.fetch($0) }
        )
        do {
            _ = try await provider.fetchQuota()
            XCTFail("Should report a connection requirement")
        } catch let error as UsageProviderError {
            guard case .credentialAccessRequired = error else { return XCTFail("Wrong failure") }
        }
        let result = try await provider.fetchQuota()
        XCTAssertEqual(result.provider, .anthropic)
        let counts = await probe.counts()
        XCTAssertEqual(counts.reads, 2)
        XCTAssertEqual(counts.requests, 1)
    }

    func testNetworkFailureRemainsRetryableNotCredentialFailure() async throws {
        let probe = RetryProbe(denyFirstRead: false, failFirstRequest: true)
        let provider = ClaudeQuotaProvider(
            loadCLI: { throw UsageProviderError.unsupported("fixture: CLI unavailable") },
            readToken: { await probe.read() },
            loadQuota: { try await probe.fetch($0) }
        )
        do {
            _ = try await provider.fetchQuota()
            XCTFail("Should propagate the network failure")
        } catch {
            XCTAssertFalse(ClaudeRefreshFailure(error: error, previous: .idle).connectionRequired)
        }
        _ = try await provider.fetchQuota()
        let counts = await probe.counts()
        XCTAssertEqual(counts.reads, 2)
        XCTAssertEqual(counts.requests, 2)
    }

    func testStaleQuotaIsRetainedWithCredentialNotice() throws {
        let snapshot = try fixture()
        let error = UsageProviderError.credentialAccessRequired("fixture")
        let notice = ClaudeRefreshFailure(error: error, previous: .loaded(snapshot))
        XCTAssertTrue(notice.connectionRequired)
        XCTAssertTrue(notice.message.contains("최신이 아닐 수"))
        let state = displayStateAfterFailedRefresh(previous: .loaded(snapshot), failure: .needsConfiguration("fixture"))
        guard case .loaded(let retained) = state else { return XCTFail("Previous quota lost") }
        XCTAssertEqual(retained.fetchedAt, snapshot.fetchedAt)
        XCTAssertEqual(retained.windows, snapshot.windows)
        XCTAssertFalse(ClaudeRefreshFailure(error: error, previous: .idle).message.contains("이전 값"))
    }

    private func fixture() throws -> QuotaSnapshot {
        try ClaudeOAuthUsageProvider.parse(["five_hour": ["utilization": 14]])
    }
}

private actor RetryProbe {
    let denyFirstRead: Bool
    let failFirstRequest: Bool
    var reads = 0
    var requests = 0

    init(denyFirstRead: Bool, failFirstRequest: Bool) {
        self.denyFirstRead = denyFirstRead
        self.failFirstRequest = failFirstRequest
    }

    func read() -> String? {
        reads += 1
        return denyFirstRead && reads == 1 ? nil : "fixture-token"
    }

    func fetch(_ token: String) throws -> QuotaSnapshot {
        requests += 1
        if failFirstRequest && requests == 1 { throw URLError(.timedOut) }
        return try ClaudeOAuthUsageProvider.parse(["five_hour": ["utilization": 14]])
    }

    func counts() -> (reads: Int, requests: Int) { (reads, requests) }
}
