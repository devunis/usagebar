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
    @Published private(set) var enabledWindowKinds: Set<QuotaWindowKind>
    @Published private(set) var enabledDisplayOptions: Set<DisplayOption>
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
        if let savedKinds = UserDefaults.standard.stringArray(forKey: Defaults.windowKinds) {
            enabledWindowKinds = Set(savedKinds.compactMap(QuotaWindowKind.init(rawValue:)))
        } else {
            enabledWindowKinds = Set(QuotaWindowKind.allCases)
        }
        if let savedOptions = UserDefaults.standard.stringArray(forKey: Defaults.displayOptions) {
            var options = Set(savedOptions.compactMap(DisplayOption.init(rawValue:)))
            if !UserDefaults.standard.bool(forKey: Defaults.didAddMenuBarUsage) {
                options.insert(.menuBarUsage)
                UserDefaults.standard.set(true, forKey: Defaults.didAddMenuBarUsage)
                UserDefaults.standard.set(
                    DisplayOption.allCases.filter(options.contains).map(\.rawValue),
                    forKey: Defaults.displayOptions
                )
            }
            enabledDisplayOptions = options
        } else {
            enabledDisplayOptions = Set(DisplayOption.allCases)
            UserDefaults.standard.set(true, forKey: Defaults.didAddMenuBarUsage)
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

    var menuBarUsageSummary: MenuBarUsageSummary? {
        guard enabledDisplayOptions.contains(.menuBarUsage) else { return nil }

        return visibleProviders.compactMap { provider -> MenuBarUsageSummary? in
            guard case .loaded(let snapshot) = states[provider],
                  let window = snapshot.windows
                    .filter({ enabledWindowKinds.contains($0.kind) })
                    .max(by: { $0.clampedPercent < $1.clampedPercent }) else {
                return nil
            }
            return MenuBarUsageSummary(
                provider: provider,
                title: window.title,
                usedPercent: window.clampedPercent
            )
        }.max(by: { $0.usedPercent < $1.usedPercent })
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
        saveProviders()
    }

    func setAllProviders(_ enabled: Bool) {
        enabledProviders = enabled ? Set(ProviderKind.allCases) : []
        if enabled {
            refreshAll()
        } else {
            states = Dictionary(
                uniqueKeysWithValues: ProviderKind.allCases.map { ($0, .idle) }
            )
        }
        saveProviders()
    }

    func isWindowKindEnabled(_ kind: QuotaWindowKind) -> Bool {
        enabledWindowKinds.contains(kind)
    }

    func setWindowKindEnabled(_ enabled: Bool, for kind: QuotaWindowKind) {
        if enabled {
            enabledWindowKinds.insert(kind)
        } else {
            enabledWindowKinds.remove(kind)
        }
        save(
            enabledWindowKinds,
            allCases: QuotaWindowKind.allCases,
            key: Defaults.windowKinds
        )
    }

    func isDisplayOptionEnabled(_ option: DisplayOption) -> Bool {
        enabledDisplayOptions.contains(option)
    }

    func setDisplayOptionEnabled(_ enabled: Bool, for option: DisplayOption) {
        if enabled {
            enabledDisplayOptions.insert(option)
        } else {
            enabledDisplayOptions.remove(option)
        }
        save(
            enabledDisplayOptions,
            allCases: DisplayOption.allCases,
            key: Defaults.displayOptions
        )
    }

    func setAllDisplayItems(_ enabled: Bool) {
        enabledWindowKinds = enabled ? Set(QuotaWindowKind.allCases) : []
        enabledDisplayOptions = enabled ? Set(DisplayOption.allCases) : []
        save(
            enabledWindowKinds,
            allCases: QuotaWindowKind.allCases,
            key: Defaults.windowKinds
        )
        save(
            enabledDisplayOptions,
            allCases: DisplayOption.allCases,
            key: Defaults.displayOptions
        )
    }

    private func saveProviders() {
        save(
            enabledProviders,
            allCases: ProviderKind.allCases,
            key: Defaults.enabledProviders
        )
    }

    private func save<Value: RawRepresentable & Hashable>(
        _ values: Set<Value>,
        allCases: [Value],
        key: String
    ) where Value.RawValue == String {
        UserDefaults.standard.set(
            allCases.filter(values.contains).map(\.rawValue),
            forKey: key
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
        static let windowKinds = "enabledWindowKinds"
        static let displayOptions = "enabledDisplayOptions"
        static let didAddMenuBarUsage = "didAddMenuBarUsageOption"
    }
}
