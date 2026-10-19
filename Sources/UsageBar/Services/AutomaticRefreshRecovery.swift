import AppKit
import Network

func shouldRefreshAfterResume(state: ProviderState, hasFailure: Bool, now: Date = Date()) -> Bool {
    if !hasFailure, case .loaded(let snapshot) = state,
       now.timeIntervalSince(snapshot.fetchedAt) < 30 { return false }
    return true
}

@MainActor
final class AutomaticRefreshRecovery {
    private let isEnabled: () -> Bool
    private let refresh: () -> Void
    private let delay: Duration
    private let retryDelay: Duration
    private var pending: Task<Void, Never>?
    private var refreshScheduled = false
    private var retriesRemaining = 0
    private var recoveryUntil: Date = .distantPast
    private var observers: [NSObjectProtocol] = []
    private var networkMonitor: NWPathMonitor?

    init(
        delay: Duration = .seconds(3),
        retryDelay: Duration = .seconds(10),
        observeSystemEvents: Bool = true,
        isEnabled: @escaping () -> Bool,
        refresh: @escaping () -> Void
    ) {
        self.delay = delay
        self.retryDelay = retryDelay
        self.isEnabled = isEnabled
        self.refresh = refresh
        guard observeSystemEvents else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.schedule() }
            })
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.schedule() }
        }
        monitor.start(queue: DispatchQueue(label: "com.usagebar.refresh-recovery"))
        networkMonitor = monitor
    }

    // Coalesce wake, login-session and network-online events. Let the connection
    // settle before refreshing, and never override the user's Manual preference.
    func schedule() {
        pending?.cancel()
        refreshScheduled = false
        guard isEnabled() else { return }
        retriesRemaining = 2
        recoveryUntil = Date().addingTimeInterval(90)
        enqueue(after: delay)
    }

    func retryAfterFailure() {
        guard isEnabled(), Date() < recoveryUntil, retriesRemaining > 0, !refreshScheduled else { return }
        retriesRemaining -= 1
        enqueue(after: retryDelay)
    }

    private func enqueue(after delay: Duration) {
        refreshScheduled = true
        pending = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.refreshScheduled = false
            guard self.isEnabled() else { return }
            self.refresh()
        }
    }

    deinit {
        pending?.cancel()
        networkMonitor?.cancel()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
