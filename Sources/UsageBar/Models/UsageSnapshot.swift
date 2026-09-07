import Foundation
import SwiftUI

enum ProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex
    case anthropic
    case gemini

    var id: String { rawValue }

    var name: String {
        switch self {
        case .codex: "ChatGPT / Codex"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        }
    }

    var shortName: String {
        switch self {
        case .codex: "G"
        case .anthropic: "C"
        case .gemini: "✦"
        }
    }

    var color: Color {
        switch self {
        case .codex: Color(red: 0.08, green: 0.65, blue: 0.52)
        case .anthropic: Color(red: 0.82, green: 0.48, blue: 0.30)
        case .gemini: Color(red: 0.34, green: 0.48, blue: 0.94)
        }
    }
}

enum QuotaWindowKind: String, CaseIterable, Identifiable, Sendable {
    case shortTerm
    case weekly
    case modelScoped

    var id: String { rawValue }

    var name: String {
        switch self {
        case .shortTerm: "단기 한도"
        case .weekly: "전체 주간 한도"
        case .modelScoped: "모델별 한도"
        }
    }
}

enum DisplayOption: String, CaseIterable, Identifiable, Sendable {
    case menuBarUsage
    case plan
    case resetTime
    case resetCredit
    case lastUpdated

    var id: String { rawValue }

    var name: String {
        switch self {
        case .menuBarUsage: "메뉴바 사용량"
        case .plan: "플랜 이름"
        case .resetTime: "리셋 시간"
        case .resetCredit: "재설정 크레딧"
        case .lastUpdated: "마지막 갱신 시간"
        }
    }
}

enum MenuBarProviderSelection: String, CaseIterable, Identifiable, Sendable {
    case highest
    case codex
    case anthropic
    case gemini

    var id: String { rawValue }

    var name: String {
        switch self {
        case .highest: "켜진 서비스 모두"
        case .codex: "ChatGPT / Codex"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        }
    }

    var provider: ProviderKind? {
        switch self {
        case .highest: nil
        case .codex: .codex
        case .anthropic: .anthropic
        case .gemini: .gemini
        }
    }
}

enum MenuBarLimitSelection: String, CaseIterable, Identifiable, Sendable {
    case highest
    case shortTerm
    case weekly
    case modelScoped

    var id: String { rawValue }

    var name: String {
        switch self {
        case .highest: "가장 높은 한도"
        case .shortTerm: "단기 한도"
        case .weekly: "전체 주간 한도"
        case .modelScoped: "모델별 한도"
        }
    }

    var windowKind: QuotaWindowKind? {
        switch self {
        case .highest: nil
        case .shortTerm: .shortTerm
        case .weekly: .weekly
        case .modelScoped: .modelScoped
        }
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable, Sendable {
    case battery
    case circular
    case minimal
    case segments
    case dualBar
    case gauge

    var id: String { rawValue }

    var name: String {
        switch self {
        case .battery: "막대형"
        case .circular: "원형"
        case .minimal: "미니멀"
        case .segments: "세그먼트"
        case .dualBar: "이중 막대"
        case .gauge: "게이지"
        }
    }

    var showsExternalPercent: Bool {
        self == .battery || self == .minimal || self == .dualBar
    }
}

enum MenuBarColorStyle: String, CaseIterable, Identifiable, Sendable {
    case provider
    case trafficLight
    case monochrome

    var id: String { rawValue }

    var name: String {
        switch self {
        case .provider: "서비스 색상"
        case .trafficLight: "사용률 경고 색상"
        case .monochrome: "단색"
        }
    }
}

struct MenuBarUsageSummary: Identifiable, Equatable, Sendable {
    let id: String
    let provider: ProviderKind
    let title: String
    let usedPercent: Double
}

struct QuotaWindow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: QuotaWindowKind
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?

    var clampedPercent: Double {
        min(max(usedPercent, 0), 100)
    }
}

enum RateLimitResetCreditStatus: String, Equatable, Sendable {
    case available
    case redeeming
    case redeemed
    case unknown
}

struct RateLimitResetCredit: Identifiable, Equatable, Sendable {
    let id: String
    let title: String?
    let detail: String?
    let grantedAt: Date
    let expiresAt: Date?
    let status: RateLimitResetCreditStatus
}

struct RateLimitResetCreditsSummary: Equatable, Sendable {
    let availableCount: Int
    let credits: [RateLimitResetCredit]?

    var nextAvailableCredit: RateLimitResetCredit? {
        credits?.first { $0.status == .available }
    }

    var earliestExpiration: Date? {
        credits?
            .filter { $0.status == .available }
            .compactMap(\.expiresAt)
            .min()
    }
}

enum ResetCreditOutcome: String, Equatable, Sendable {
    case reset
    case nothingToReset
    case noCredit
    case alreadyRedeemed
}

struct QuotaSnapshot: Identifiable, Equatable, Sendable {
    let provider: ProviderKind
    let windows: [QuotaWindow]
    let plan: String?
    let fetchedAt: Date
    let resetCredits: RateLimitResetCreditsSummary?

    init(
        provider: ProviderKind,
        windows: [QuotaWindow],
        plan: String?,
        fetchedAt: Date,
        resetCredits: RateLimitResetCreditsSummary? = nil
    ) {
        self.provider = provider
        self.windows = windows
        self.plan = plan
        self.fetchedAt = fetchedAt
        self.resetCredits = resetCredits
    }

    var id: ProviderKind { provider }
}

enum ProviderState: Equatable {
    case idle
    case loading
    case loaded(QuotaSnapshot)
    case needsConfiguration(String)
    case failed(String)
}
