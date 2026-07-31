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
    @Published private(set) var enabledProviders: Set<ProviderKind>
    private var timerTask: Task<Void, Never>?

    init() {
        let savedInterval = UserDefaults.standard.integer(forKey: Defaults.refreshInterval)
        refreshIntervalMinutes = savedInterval == 0 ? 15 : savedInterval
        if let savedProviders = UserDefaults.standard.stringArray(
            forKey: Defaults.enabledProviders
        ) {
            enabledProviders = Set(savedProviders.compactMap(ProviderKind.init(rawValue:)))
        } else {
            enabledProviders = [.codex, .anthropic]
        }
        restartTimer()
    }

    deinit {
        timerTask?.cancel()
    }

    func refreshAll() {
        for kind in visibleProviders {
            refresh(kind)
        }
    }

    func refresh(_ kind: ProviderKind) {
        guard enabledProviders.contains(kind) else { return }
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

    var visibleProviders: [ProviderKind] {
        ProviderKind.allCases.filter(enabledProviders.contains)
    }

    func isEnabled(_ kind: ProviderKind) -> Bool {
        enabledProviders.contains(kind)
    }

    func setEnabled(_ enabled: Bool, for kind: ProviderKind) {
        if enabled {
            enabledProviders.insert(kind)
            refresh(kind)
        } else {
            enabledProviders.remove(kind)
            states[kind] = .idle
        }
        UserDefaults.standard.set(
            ProviderKind.allCases
                .filter(enabledProviders.contains)
                .map(\.rawValue),
            forKey: Defaults.enabledProviders
        )
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
        static let enabledProviders = "enabledProviders"
    }
}
