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
    private var timerTask: Task<Void, Never>?

    init() {
        let savedInterval = UserDefaults.standard.integer(forKey: Defaults.refreshInterval)
        refreshIntervalMinutes = savedInterval == 0 ? 15 : savedInterval
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

        Task {
            do {
                let provider: any QuotaProvider = switch kind {
                case .codex:
                    CodexQuotaProvider()
                case .anthropic:
                    ClaudeQuotaProvider()
                case .gemini:
                    GeminiQuotaProvider()
                }
                let snapshot = try await provider.fetchQuota()
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
    }
}
