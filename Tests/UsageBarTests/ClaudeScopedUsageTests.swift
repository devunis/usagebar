import XCTest
@testable import UsageBar

final class ClaudeScopedUsageTests: XCTestCase {
    private func scoped(_ name: String, percent: Any, active: Bool = false) -> [String: Any] {
        ["kind": "weekly_scoped", "percent": percent, "is_active": active,
         "resets_at": "2026-10-26T03:00:00Z", "scope": ["model": ["display_name": name]]]
    }

    func testFableInModernLimitsIsNotDroppedWhenInactive() throws {
        let snapshot = try ClaudeOAuthUsageProvider.parse([
            "five_hour": ["utilization": 6], "seven_day": ["utilization": 21],
            "seven_day_fable": NSNull(), "limits": [scoped("Fable", percent: 14)]
        ])
        XCTAssertEqual(snapshot.windows.map(\.title), ["5시간", "주간", "Fable 주간"])
        let fable = try XCTUnwrap(snapshot.windows.last)
        XCTAssertEqual(fable.usedPercent, 14)
        XCTAssertEqual(fable.kind, .modelScoped)
        XCTAssertEqual(fable.durationMinutes, 10_080)
        XCTAssertNotNil(fable.resetsAt)
    }

    func testZeroPercentFableIsMeasuredNotMissing() throws {
        let snapshot = try ClaudeOAuthUsageProvider.parse(["limits": [scoped("Fable", percent: 0)]])
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 0)
        XCTAssertEqual(snapshot.windows.first?.title, "Fable 주간")
    }

    func testArrayOnlyMainWindowsKeepSessionWeeklyModelsOrder() throws {
        let snapshot = try ClaudeOAuthUsageProvider.parse([
            "five_hour": NSNull(), "seven_day": NSNull(),
            "limits": [scoped("Fable", percent: 12),
                       ["kind": "weekly_all", "percent": 20, "is_active": false],
                       ["kind": "session", "percent": 8]]
        ])
        XCTAssertEqual(snapshot.windows.map(\.title), ["5시간", "주간", "Fable 주간"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [8, 20, 12])
    }

    func testModernScopedMeasurementWinsWithoutDuplicatingLegacyModel() throws {
        let snapshot = try ClaudeOAuthUsageProvider.parse([
            "seven_day_fable": ["utilization": 5], "seven_day_sonnet": ["utilization": 7],
            "limits": [scoped("Fable", percent: 18), scoped("fable", percent: 20)]
        ])
        XCTAssertEqual(snapshot.windows.map(\.title), ["Fable 주간", "Sonnet 주간"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [18, 7])
    }

    func testMalformedScopedRowsDoNotInventZeroOrDiscardOtherQuotas() throws {
        let snapshot = try ClaudeOAuthUsageProvider.parse([
            "five_hour": ["utilization": 9],
            "limits": [NSNull(), scoped("Unknown", percent: NSNull()), scoped("Boolean", percent: true),
                       scoped("Invalid", percent: 101), scoped("", percent: 5),
                       scoped("All models", percent: 20), scoped("Fable", percent: 3)] as [Any]
        ])
        XCTAssertEqual(snapshot.windows.map(\.title), ["5시간", "Fable 주간"])
    }

    func testExpiredCredentialIsNotMisreportedAsMissingKeychainPermission() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": ["accessToken": "fixture-token", "expiresAt": now.timeIntervalSince1970 * 1000]
        ])
        let credential = ClaudeOAuthUsageProvider.parseCredential(in: data, now: now)
        XCTAssertThrowsError(try credential.tokenForUsage()) { error in
            guard let error = error as? UsageProviderError, case .credentialExpired = error else {
                return XCTFail("Expiry must not become an access permission error")
            }
            XCTAssertFalse(ClaudeRefreshFailure(error: error, previous: .idle).connectionRequired)
        }
        let renewed = ClaudeOAuthUsageProvider.parseCredential(in: data, now: now.addingTimeInterval(-1))
        XCTAssertNotNil(try renewed.tokenForUsage())
    }

    func testKeychainDenialIsNotReportedAsTokenExpiry() {
        XCTAssertThrowsError(try ClaudeCredentialRead.keychainUnavailable(-25293).tokenForUsage()) { error in
            guard let error = error as? UsageProviderError, case .credentialAccessRequired = error else {
                return XCTFail("Keychain denial must remain distinct from expiry")
            }
            XCTAssertTrue(ClaudeRefreshFailure(error: error, previous: .idle).connectionRequired)
        }
    }
}
