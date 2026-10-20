import XCTest
@testable import UsageBar

final class ClaudeCLIUsageTests: XCTestCase {
    private var payload: [String: Any] {
        ["rate_limits_available": true, "subscription_type": "max", "rate_limits": [
            "five_hour": ["utilization": 84, "resets_at": "2026-10-21T12:00:00Z"],
            "seven_day": ["utilization": 11],
            "model_scoped": [["display_name": "Fable", "utilization": 10,
                              "resets_at": "2026-10-26T03:00:00Z"]]
        ]]
    }

    func testStructuredCLIResponseIncludesFableAndMainWindows() throws {
        let snapshot = try ClaudeCLIUsageProvider.parse(payload)
        XCTAssertEqual(snapshot.windows.map(\.title), ["5시간", "주간", "Fable 주간"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [84, 11, 10])
        XCTAssertEqual(snapshot.plan, "max")
        XCTAssertNotNil(snapshot.windows.last?.resetsAt)
        XCTAssertEqual(snapshot.claudeBenefits, .cliUnavailable)
    }

    func testUnknownScopedQuotaIsNotZeroAndKnownZeroIsVisible() throws {
        let snapshot = try ClaudeCLIUsageProvider.parse([
            "rate_limits_available": true, "rate_limits": [
                "five_hour": ["utilization": 4],
                "model_scoped": [["display_name": "Fable", "utilization": 0],
                                 ["display_name": "Unknown", "utilization": NSNull()]]
            ]
        ])
        XCTAssertEqual(snapshot.windows.map(\.title), ["5시간", "Fable 주간"])
        XCTAssertEqual(snapshot.windows.last?.usedPercent, 0)
        XCTAssertThrowsError(try ClaudeCLIUsageProvider.parse(["rate_limits_available": false]))
    }

    func testProtocolOnlyRequestsUsageAfterMatchingInitialize() throws {
        var session = ClaudeUsageControlSession()
        guard case .ignore = try session.receive(response("usagebar-usage", payload)) else {
            return XCTFail("Unsolicited usage must be ignored")
        }
        guard case .ignore = try session.receive(response("other-session", [:])) else {
            return XCTFail("Unrelated responses must be ignored")
        }
        guard case .requestUsage = try session.receive(response("usagebar-initialize", [:])) else {
            return XCTFail("Initialize must precede get_usage")
        }
        XCTAssertEqual((session.usageRequest["request"] as? [String: Any])?["skip_behaviors"] as? Bool, true)
        guard case .usage(let result) = try session.receive(response("usagebar-usage", payload)) else {
            return XCTFail("Usage result not delivered")
        }
        XCTAssertEqual(result["rate_limits_available"] as? Bool, true)
        XCTAssertThrowsError(try session.receive(["type": "control_request", "request": ["subtype": "can_use_tool"]]))
        XCTAssertThrowsError(try session.receive([
            "type": "control_response", "response": ["request_id": "usagebar-usage", "subtype": "error", "error": "PRIVATE_DETAIL"]
        ])) { error in
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_DETAIL"))
        }
    }

    func testCLISuccessNeverReadsCredentials() async throws {
        let fixture = try ClaudeCLIUsageProvider.parse(payload)
        let probe = PriorityProbe(snapshot: fixture, cliFails: false)
        let result = try await provider(probe).fetchQuota()
        XCTAssertEqual(result.windows, fixture.windows)
        let calls = await probe.calls
        XCTAssertEqual(calls, ["cli"])
    }

    func testCLIFailureUsesNoninteractiveCredentialsSecond() async throws {
        let probe = PriorityProbe(snapshot: try ClaudeCLIUsageProvider.parse(payload), cliFails: true)
        _ = try await provider(probe).fetchQuota()
        let calls = await probe.calls
        XCTAssertEqual(calls, ["cli", "credential", "oauth"])
    }

    func testCancelledCLIDoesNotReadCredentials() async throws {
        let provider = ClaudeQuotaProvider(
            loadCLI: { throw CancellationError() },
            readToken: { XCTFail("Cancellation must not read credentials"); return nil },
            loadQuota: { _ in XCTFail("Cancellation must not contact OAuth"); throw CancellationError() }
        )
        do { _ = try await provider.fetchQuota(); XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
    }

    func testTransportUsesOnlyControlRequestsAndReadsFable() async throws {
        let initJSON = try json(response("usagebar-initialize", [:]))
        let usageJSON = try json(response("usagebar-usage", payload))
        let script = """
        #!/bin/sh
        IFS= read -r initialize
        case "$initialize" in *usagebar-initialize*) ;; *) exit 3;; esac
        printf '%s\\n' '\(initJSON)'
        IFS= read -r usage
        case "$usage" in *get_usage*) ;; *) exit 4;; esac
        case "$usage" in *skip_behaviors*) ;; *) exit 5;; esac
        printf '%s\\n' '\(usageJSON)'
        """
        let fixture = try executableFixture(script)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let result = try await ClaudeCLIUsageProvider(executable: fixture.executable, workingDirectory: fixture.directory,
                                                    timeout: 2).fetchQuota()
        XCTAssertEqual(result.windows.map(\.usedPercent), [84, 11, 10])
        XCTAssertFalse(ClaudeCLIUsageProvider.arguments.contains("--dangerously-skip-permissions"))
        XCTAssertTrue(ClaudeCLIUsageProvider.arguments.contains("--safe-mode"))
        XCTAssertTrue(ClaudeCLIUsageProvider.arguments.contains("--strict-mcp-config"))
    }

    func testUnresponsiveProbeTimesOutAndDoesNotExposeRawStderr() async throws {
        let script = """
        #!/bin/sh
        printf '%s\\n' 'PRIVATE_DETAIL' >&2
        while IFS= read -r request; do :; done
        """
        let fixture = try executableFixture(script)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let start = Date()
        do {
            _ = try await ClaudeCLIUsageProvider(executable: fixture.executable, workingDirectory: fixture.directory,
                                                timeout: 0.15).fetchQuota()
            XCTFail("Expected timeout")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_DETAIL"))
            XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        }
    }

    func testCLIExitingAfterInitializeDoesNotCrashHost() async throws {
        let initJSON = try json(response("usagebar-initialize", [:]))
        let fixture = try executableFixture("""
        #!/bin/sh
        IFS= read -r initialize
        printf '%s\\n' '\(initJSON)'
        exit 0
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        do {
            _ = try await ClaudeCLIUsageProvider(executable: fixture.executable, workingDirectory: fixture.directory,
                                                timeout: 0.5).fetchQuota()
            XCTFail("Expected missing response")
        } catch { /* Early exit or broken pipe must be recoverable, not SIGPIPE. */ }
    }

    func testCancellingUnresponsiveTransportStopsProbePromptly() async throws {
        let fixture = try executableFixture("#!/bin/sh\nwhile IFS= read -r request; do :; done\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let task = Task {
            try await ClaudeCLIUsageProvider(executable: fixture.executable, workingDirectory: fixture.directory,
                                             timeout: 20).fetchQuota()
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
    }

    private func response(_ id: String, _ payload: [String: Any]) -> [String: Any] {
        ["type": "control_response", "response": ["subtype": "success", "request_id": id, "response": payload]]
    }
    private func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
    private func executableFixture(_ script: String) throws -> (directory: URL, executable: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("usagebar-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-claude")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (directory, executable)
    }
    private func provider(_ probe: PriorityProbe) -> ClaudeQuotaProvider {
        ClaudeQuotaProvider(loadCLI: { try await probe.cli() }, readToken: { await probe.credential() },
                            loadQuota: { _ in await probe.oauth() })
    }
}

private actor PriorityProbe {
    let snapshot: QuotaSnapshot
    let cliFails: Bool
    var calls: [String] = []
    init(snapshot: QuotaSnapshot, cliFails: Bool) { self.snapshot = snapshot; self.cliFails = cliFails }
    func cli() throws -> QuotaSnapshot {
        calls.append("cli")
        if cliFails { throw UsageProviderError.commandFailed("fixture") }
        return snapshot
    }
    func credential() -> String? { calls.append("credential"); return "fixture-token" }
    func oauth() -> QuotaSnapshot { calls.append("oauth"); return snapshot }
}
