import AppKit
import SwiftUI

private typealias MenuHeightState = State<CGFloat>

private struct ProviderContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openSettings) private var openSettings
    @MenuHeightState private var providerContentHeight: CGFloat = 0

    private var maximumProviderHeight: CGFloat {
        max(240, (NSScreen.main?.visibleFrame.height ?? 800) - 160)
    }

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
                    store.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("모두 새로고침")
            }

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(store.visibleProviders) { kind in
                        ProviderCard(
                            kind: kind,
                            state: store.states[kind] ?? .idle,
                            isRefreshing: store.isRefreshing(kind),
                            enabledWindowKinds: store.enabledWindowKinds,
                            enabledDisplayOptions: store.enabledDisplayOptions,
                            isConsumingResetCredit: store.isConsumingCodexResetCredit,
                            resetMessage: kind == .codex ? store.codexResetMessage : nil,
                            refresh: {
                                store.refresh(kind)
                            },
                            consumeResetCredit: { creditID in
                                store.consumeCodexResetCredit(creditID: creditID)
                            },
                            connectClaudeBenefits: { store.connectClaudeBenefits() },
                            claudeBenefitsMessage: store.claudeBenefitsMessage
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ProviderContentHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // Keep an explicit viewport height so MenuBarExtra cannot collapse it,
            // while fitting short content and using the screen for longer content.
            .frame(height: store.visibleProviders.isEmpty ? 0 : min(
                providerContentHeight > 0 ? providerContentHeight : maximumProviderHeight,
                maximumProviderHeight
            ))
            .onPreferenceChange(ProviderContentHeightKey.self) { height in
                if height.isFinite && abs(providerContentHeight - height) > 0.5 {
                    providerContentHeight = height
                }
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
