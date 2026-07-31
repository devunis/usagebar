import XCTest
@testable import UsageBar

final class UsageDecoderTests: XCTestCase {
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

    func testClaudeUsageParsesWeeklyWindow() throws {
        let data = Data(
            """
            {
              "five_hour": {"utilization": 22.5, "resets_at": "2026-08-01T01:00:00Z"},
              "seven_day": {"utilization": 48, "resets_at": "2026-08-05T01:00:00Z"}
            }
            """.utf8
        )

        let snapshot = try ClaudeQuotaProvider.parse(data)
        XCTAssertEqual(snapshot.windows.map(\.title), ["5시간", "주간"])
        XCTAssertEqual(snapshot.windows[1].usedPercent, 48)
        XCTAssertNotNil(snapshot.windows[1].resetsAt)
    }

    func testClaudeUsageParsesFableScopedWeeklyWindow() throws {
        let data = Data(
            """
            {
              "five_hour": {"utilization": 22.5, "resets_at": "2026-08-01T01:00:00Z"},
              "seven_day": {"utilization": 48, "resets_at": "2026-08-05T01:00:00Z"},
              "limits": [
                {
                  "kind": "weekly_scoped",
                  "percent": 67.5,
                  "resets_at": "2026-08-05T01:00:00Z",
                  "scope": {"model": {"display_name": "Fable"}}
                }
              ]
            }
            """.utf8
        )

        let snapshot = try ClaudeQuotaProvider.parse(data)
        let fable = try XCTUnwrap(snapshot.windows.first { $0.title == "Fable 주간" })
        XCTAssertEqual(fable.usedPercent, 67.5)
        XCTAssertEqual(fable.durationMinutes, 10_080)
        XCTAssertNotNil(fable.resetsAt)
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
        XCTAssertEqual(segments.map(\.filledCount), [3, 2, 1])
        XCTAssertEqual(segments.map(\.emptyCount), [2, 3, 4])
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
}
