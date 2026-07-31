import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var states: [ProviderKind: ProviderState] = Dictionary(
        uniqueKeysWithValues: ProviderKind.allCases.map { ($0, .idle) }
    )
    @Published var refreshIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: Defaults.refreshInterval)
            restartTimer()
        }
    }
    @Published var geminiProjectID: String {
        didSet {
            UserDefaults.standard.set(geminiProjectID, forKey: Defaults.geminiProjectID)
        }
    }
    @Published var settingsMessage: String?

    private var timerTask: Task<Void, Never>?

    init() {
        let savedInterval = UserDefaults.standard.integer(forKey: Defaults.refreshInterval)
        refreshIntervalMinutes = savedInterval == 0 ? 15 : savedInterval
        geminiProjectID = UserDefaults.standard.string(forKey: Defaults.geminiProjectID) ?? ""
        restartTimer()
    }

    deinit {
        timerTask?.cancel()
    }

    func refreshAll() {
        for kind in ProviderKind.allCases {
            refresh(kind)
        }
    }

    func refresh(_ kind: ProviderKind) {
        states[kind] = .loading
        let projectID = geminiProjectID

        Task {
            do {
                let now = Date()
                let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
                let provider: any UsageProvider = switch kind {
                case .openAI:
                    OpenAIUsageProvider()
                case .anthropic:
                    AnthropicUsageProvider()
                case .gemini:
                    GeminiUsageProvider(projectID: projectID)
                }
                let snapshot = try await provider.fetchUsage(from: start, to: now)
                states[kind] = .loaded(snapshot)
            } catch let error as UsageProviderError {
                switch error {
                case .missingCredential(let message):
                    states[kind] = .needsConfiguration(message)
                default:
                    states[kind] = .failed(error.localizedDescription)
                }
            } catch {
                states[kind] = .failed(error.localizedDescription)
            }
        }
    }

    func saveCredentials(openAI: String, anthropic: String) {
        do {
            try updateKey(openAI, account: CredentialAccount.openAI)
            try updateKey(anthropic, account: CredentialAccount.anthropic)
            settingsMessage = "Keychain에 안전하게 저장했습니다."
            refreshAll()
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func storedCredential(for account: String) -> String {
        KeychainStore.shared.value(for: account) ?? ""
    }

    private func updateKey(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try KeychainStore.shared.delete(account)
        } else {
            try KeychainStore.shared.set(trimmed, for: account)
        }
    }

    private func restartTimer() {
        timerTask?.cancel()
        let interval = refreshIntervalMinutes
        timerTask = Task { [weak self] in
            guard interval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval * 60))
                guard !Task.isCancelled else { return }
                self?.refreshAll()
            }
        }
    }

    private enum Defaults {
        static let refreshInterval = "refreshIntervalMinutes"
        static let geminiProjectID = "geminiProjectID"
    }
}
