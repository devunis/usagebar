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

struct QuotaWindow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?

    var clampedPercent: Double {
        min(max(usedPercent, 0), 100)
    }
}

struct QuotaSnapshot: Identifiable, Equatable, Sendable {
    let provider: ProviderKind
    let windows: [QuotaWindow]
    let plan: String?
    let fetchedAt: Date

    var id: ProviderKind { provider }
}

enum ProviderState: Equatable {
    case idle
    case loading
    case loaded(QuotaSnapshot)
    case needsConfiguration(String)
    case failed(String)
}
