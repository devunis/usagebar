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
                    Text("AI API 사용량 한눈에 보기")
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

            ForEach(ProviderKind.allCases) { kind in
                ProviderCard(
                    kind: kind,
                    state: store.states[kind] ?? .idle,
                    refresh: { store.refresh(kind) }
                )
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
        .frame(width: 370)
        .task {
            store.refreshAll()
        }
    }
}
