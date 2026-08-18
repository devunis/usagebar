import XCTest
@testable import UsageBar

final class UsageDecoderTests: XCTestCase {
    func testCLIWorkingDirectoryIsScopedBelowUsageBarSupportFolder() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let directory = try cliWorkingDirectory(
            for: "claude/code",
            applicationSupportDirectory: baseDirectory
        )

        XCTAssertEqual(
            directory.standardizedFileURL.path,
            baseDirectory
                .appendingPathComponent("UsageBar/CLIWorkspaces/claude-code")
                .standardizedFileURL.path
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.path)
        )
        XCTAssertNotEqual(directory.standardizedFileURL.path, "/")
    }

    func testLiveClaudeQuotaWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["USAGEBAR_LIVE_CLAUDE_TEST"] == "1" else {
            throw XCTSkip(
                "USAGEBAR_LIVE_CLAUDE_TEST=1일 때만 Claude CLI 로그인 세션을 확인합니다."
            )
        }

        let snapshot = try await ClaudeQuotaProvider().fetchQuota()
        XCTAssertEqual(snapshot.provider, .anthropic)
        XCTAssertEqual(snapshot.windows.map(\.title), ["5시간", "주간", "Fable 주간"])
        XCTAssertTrue(snapshot.windows.allSatisfy { (0...100).contains($0.clampedPercent) })
    }

    func testLiveCodexQuotaWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["USAGEBAR_LIVE_TEST"] == "1" else {
            throw XCTSkip("USAGEBAR_LIVE_TEST=1일 때만 로컬 로그인 세션을 확인합니다.")
        }

        let snapshot = try await CodexQuotaProvider().fetchQuota()
        XCTAssertFalse(snapshot.windows.isEmpty)
        XCTAssertTrue(snapshot.windows.allSatisfy { (0...100).contains($0.clampedPercent) })
    }

    func testCodexRateLimitsParseWeeklyAndFiveHourWindows() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "codex",
                "planType": "plus",
                "primary": [
                    "usedPercent": 38,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_800_000_000
                ],
                "secondary": [
                    "usedPercent": 12.5,
                    "windowDurationMins": 300,
                    "resetsAt": 1_799_000_000
                ]
            ]
        ]

        let snapshot = try CodexQuotaProvider.parse(result)
        XCTAssertEqual(snapshot.plan, "plus")
        XCTAssertEqual(snapshot.windows.map(\.title), ["주간", "5시간 보조"])
        XCTAssertEqual(snapshot.windows[0].usedPercent, 38)
    }

    func testClaudeCLIUsageParsesAllLimitWindows() throws {
        let snapshot = try ClaudeQuotaProvider.parseCLIUsage(
            """
            You are currently using your subscription to power your Claude Code usage

            Current session: 12.5% used · resets August 18, 2026 at 4:00 PM
            Current week (all models): 34% used · resets August 18, 2026 at 9:00 AM
            Current week (Fable): 14% used · resets August 18, 2026 at 9:00 AM
            """
        )

        XCTAssertEqual(snapshot.windows.map(\.title), ["5시간", "주간", "Fable 주간"])
        XCTAssertEqual(snapshot.windows.map(\.kind), [.shortTerm, .weekly, .modelScoped])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [12.5, 34, 14])
        XCTAssertEqual(snapshot.windows.map(\.durationMinutes), [300, 10_080, 10_080])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.resetsAt != nil })
    }

    func testClaudeCLIUsageWithoutPlanLimitsRequiresLogin() throws {
        XCTAssertThrowsError(
            try ClaudeQuotaProvider.parseCLIUsage(
                """
                Total cost:            $0.0000
                Total duration (API):  0s
                Usage:                 0 input, 0 output
                """
            )
        ) { error in
            guard case UsageProviderError.missingCredential(let message) = error else {
                return XCTFail("로그인 안내 오류가 아닙니다: \(error)")
            }
            XCTAssertTrue(message.contains("claude auth login"))
        }
    }

    func testGeminiQuotaUsesMostRestrictiveBucketPerModel() throws {
        let data = Data(
            """
            {
              "buckets": [
                {"modelId": "gemini-2.5-pro", "remainingFraction": 0.75, "resetTime": "2026-08-01T01:00:00Z"},
                {"modelId": "gemini-2.5-pro", "remainingFraction": 0.40, "resetTime": "2026-08-01T02:00:00Z"},
                {"modelId": "gemini-2.5-flash", "remainingFraction": 0.90}
              ]
            }
            """.utf8
        )

        let snapshot = try GeminiQuotaProvider.parse(data)
        let pro = try XCTUnwrap(snapshot.windows.first { $0.id == "gemini-2.5-pro" })
        XCTAssertEqual(pro.usedPercent, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows.count, 2)
    }

    func testWindowTitleFormatting() {
        XCTAssertEqual(windowTitle(10_080), "주간")
        XCTAssertEqual(windowTitle(300), "5시간")
        XCTAssertEqual(windowTitle(60), "1시간")
    }

    func testMenuBarBuildsAllRequestedUsageSegments() {
        let summaries = [
            MenuBarUsageSummary(
                id: "codex-weekly",
                provider: .codex,
                title: "주간",
                usedPercent: 56
            ),
            MenuBarUsageSummary(
                id: "claude-weekly",
                provider: .anthropic,
                title: "주간",
                usedPercent: 34
            ),
            MenuBarUsageSummary(
                id: "gemini-model",
                provider: .gemini,
                title: "Gemini Pro",
                usedPercent: 14
            )
        ]

        let segments = makeMenuBarStatusSegments(from: summaries)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.map(\.percentText), ["56%", "34%", "14%"])
        XCTAssertEqual(segments.map(\.fillFraction), [0.56, 0.34, 0.14])
    }

    func testClaudeMenuBarSelectsOneConfiguredWindow() throws {
        let windows = [
            QuotaWindow(
                id: "five-hour",
                title: "5시간",
                kind: .shortTerm,
                usedPercent: 7,
                durationMinutes: 300,
                resetsAt: nil
            ),
            QuotaWindow(
                id: "weekly",
                title: "주간",
                kind: .weekly,
                usedPercent: 34,
                durationMinutes: 10_080,
                resetsAt: nil
            ),
            QuotaWindow(
                id: "fable",
                title: "Fable 주간",
                kind: .modelScoped,
                usedPercent: 14,
                durationMinutes: 10_080,
                resetsAt: nil
            )
        ]
        let enabledKinds = Set(QuotaWindowKind.allCases)

        XCTAssertEqual(
            preferredMenuBarWindow(
                from: windows,
                enabledKinds: enabledKinds,
                selection: .shortTerm
            )?.id,
            "five-hour"
        )
        XCTAssertEqual(
            preferredMenuBarWindow(
                from: windows,
                enabledKinds: enabledKinds,
                selection: .weekly
            )?.id,
            "weekly"
        )
        XCTAssertEqual(
            preferredMenuBarWindow(
                from: windows,
                enabledKinds: enabledKinds,
                selection: .modelScoped
            )?.id,
            "fable"
        )
    }

    func testRefreshingKeepsPreviousSnapshotVisible() {
        let snapshot = QuotaSnapshot(
            provider: .codex,
            windows: [],
            plan: "plus",
            fetchedAt: Date()
        )
        let loaded = ProviderState.loaded(snapshot)

        XCTAssertEqual(displayStateWhileRefreshing(loaded), loaded)
        XCTAssertEqual(
            displayStateAfterFailedRefresh(
                previous: loaded,
                failure: .failed("network")
            ),
            loaded
        )
        XCTAssertEqual(displayStateWhileRefreshing(.idle), .loading)
        XCTAssertEqual(
            displayStateAfterFailedRefresh(
                previous: .idle,
                failure: .failed("network")
            ),
            .failed("network")
        )
    }
}
