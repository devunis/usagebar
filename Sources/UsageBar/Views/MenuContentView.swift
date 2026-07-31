import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore

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

            ForEach(store.visibleProviders) { kind in
                ProviderCard(
                    kind: kind,
                    state: store.states[kind] ?? .idle,
                    enabledWindowKinds: store.enabledWindowKinds,
                    enabledDisplayOptions: store.enabledDisplayOptions,
                    refresh: { store.refresh(kind) }
                )
            }

            if store.visibleProviders.isEmpty {
                Text("설정에서 표시할 서비스를 선택해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                SettingsLink {
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
}
