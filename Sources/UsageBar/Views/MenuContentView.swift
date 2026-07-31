import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UsageBar")
                        .font(.title3.bold())
                    Text("AI 구독 한도와 리셋 시간")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.refreshAll(allowsCredentialPrompt: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("모두 새로고침")
            }

            ForEach(store.visibleProviders) { kind in
                ProviderCard(
                    kind: kind,
                    state: store.states[kind] ?? .idle,
                    isRefreshing: store.isRefreshing(kind),
                    enabledWindowKinds: store.enabledWindowKinds,
                    enabledDisplayOptions: store.enabledDisplayOptions,
                    refresh: {
                        store.refresh(kind, allowsCredentialPrompt: true)
                    }
                )
            }

            if store.visibleProviders.isEmpty {
                Text("설정에서 표시할 서비스를 선택해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    showSettings()
                } label: {
                    Label("설정", systemImage: "gearshape")
                }
                .buttonStyle(.plain)

                Spacer()

                Button("종료") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 410)
        .task {
            store.refreshAll()
        }
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        bringSettingsToFront(attemptsRemaining: 6)
    }

    private func bringSettingsToFront(attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            let settingsWindows = NSApp.windows.filter {
                $0.isVisible &&
                    $0.styleMask.contains(.titled) &&
                    !($0 is NSPanel)
            }
            if let settingsWindow = settingsWindows.first {
                settingsWindow.orderFrontRegardless()
                settingsWindow.makeKey()
            } else if attemptsRemaining > 1 {
                bringSettingsToFront(attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }
}
