import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        Form {
            Section("연결 방식") {
                Text("API 키를 저장하지 않습니다. 각 공식 CLI에 로그인된 계정의 한도만 읽습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                connection("ChatGPT / Codex", command: "codex login")
                connection("Claude", command: "claude auth login")
                connection("Gemini", command: "gemini")
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
        .frame(width: 520, height: 390)
    }

    private func connection(_ name: String, command: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
