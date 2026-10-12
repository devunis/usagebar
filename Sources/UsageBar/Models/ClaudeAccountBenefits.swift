import Foundation

struct ClaudeResetGrant: Equatable, Sendable {
    let remaining: Int
    let startsAt: Date
    let expiresAt: Date
    let paused: Bool

    func isAvailable(at now: Date) -> Bool {
        !paused && startsAt <= now && now < expiresAt && remaining > 0
    }
}

struct ClaudeResetInventory: Equatable, Sendable {
    let grants: [ClaudeResetGrant]

    func availableCount(at now: Date) -> Int {
        grants.filter { $0.isAvailable(at: now) }.reduce(0) { $0 + $1.remaining }
    }

    func nextExpiration(at now: Date) -> Date? {
        grants.filter { $0.isAvailable(at: now) }.map(\.expiresAt).min()
    }
}

struct ClaudeCloudCredits: Equatable, Sendable {
    let allowanceUSD: Double
    let remainingUSD: Double
    let expiresAt: Date?
    let locked: Bool

    var usedPercent: Double {
        min(100, max(0, (1 - remainingUSD / allowanceUSD) * 100))
    }

    func isExpired(at now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }
}

struct ClaudeAccountBenefits: Equatable, Sendable {
    let resets: ClaudeResetInventory?
    let cloudCredits: ClaudeCloudCredits?
    let unavailableMessage: String?

    static let unavailable = ClaudeAccountBenefits(
        resets: nil,
        cloudCredits: nil,
        unavailableMessage: "추가 정보 조회 불가 · Claude 사용량 화면에서 확인해 주세요."
    )
}
