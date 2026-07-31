import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        Form {
            Section("서비스") {
                Text("API 키를 저장하지 않습니다. 각 공식 CLI에 로그인된 계정의 한도만 읽습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                providerToggle(.codex, command: "codex login")
                providerToggle(.anthropic, command: "claude auth login")
                providerToggle(.gemini, command: "gemini")

                HStack {
                    Button("모두 켜기") {
                        store.setAllProviders(true)
                    }
                    Button("모두 끄기") {
                        store.setAllProviders(false)
                    }
                }
            }

            Section("표시 항목") {
                ForEach(QuotaWindowKind.allCases) { kind in
                    Toggle(kind.name, isOn: Binding(
                        get: { store.isWindowKindEnabled(kind) },
                        set: { store.setWindowKindEnabled($0, for: kind) }
                    ))
                }
                ForEach(DisplayOption.allCases) { option in
                    Toggle(option.name, isOn: Binding(
                        get: { store.isDisplayOptionEnabled(option) },
                        set: { store.setDisplayOptionEnabled($0, for: option) }
                    ))
                }

                HStack {
                    Button("모두 표시") {
                        store.setAllDisplayItems(true)
                    }
                    Button("모두 숨기기") {
                        store.setAllDisplayItems(false)
                    }
                }
            }

            Section("자동 새로고침") {
                Picker("주기", selection: $store.refreshIntervalMinutes) {
                    Text("수동").tag(0)
                    Text("5분").tag(5)
                    Text("15분").tag(15)
                    Text("30분").tag(30)
                    Text("60분").tag(60)
                }
            }

            Section {
                Button("지금 모두 새로고침") {
                    store.refreshAll()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 650)
    }

    private func providerToggle(_ kind: ProviderKind, command: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(kind.name, isOn: Binding(
                get: { store.isEnabled(kind) },
                set: { store.setEnabled($0, for: kind) }
            ))
            Text(command)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .padding(.leading, 20)
        }
    }
}
