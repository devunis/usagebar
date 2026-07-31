import Foundation
import SwiftUI

enum ProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI
    case anthropic
    case gemini

    var id: String { rawValue }

    var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        }
    }

    var shortName: String {
        switch self {
        case .openAI: "O"
        case .anthropic: "C"
        case .gemini: "G"
        }
    }

    var color: Color {
        switch self {
        case .openAI: Color(red: 0.08, green: 0.65, blue: 0.52)
        case .anthropic: Color(red: 0.82, green: 0.48, blue: 0.30)
        case .gemini: Color(red: 0.34, green: 0.48, blue: 0.94)
        }
    }
}

struct UsageSnapshot: Identifiable, Equatable, Sendable {
    let provider: ProviderKind
    let inputTokens: Int
    let outputTokens: Int
    let requests: Int
    let periodStart: Date
    let periodEnd: Date
    let fetchedAt: Date

    var id: ProviderKind { provider }
    var totalTokens: Int { inputTokens + outputTokens }

    static func empty(for provider: ProviderKind, now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            inputTokens: 0,
            outputTokens: 0,
            requests: 0,
            periodStart: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now,
            periodEnd: now,
            fetchedAt: now
        )
    }
}

enum ProviderState: Equatable {
    case idle
    case loading
    case loaded(UsageSnapshot)
    case needsConfiguration(String)
    case failed(String)
}

extension Int {
    var compactUsage: String {
        let value = Double(self)
        switch abs(self) {
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", value / 1_000)
        default:
            return formatted()
        }
    }
}
