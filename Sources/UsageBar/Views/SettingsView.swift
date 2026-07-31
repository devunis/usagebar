import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("Admin API 키", text: $openAIKey)
                Text("조직 Usage API에 접근 가능한 Admin 키가 필요합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Anthropic") {
                SecureField("Admin API 키", text: $anthropicKey)
                Text("Console에서 발급한 조직 Admin 키가 필요합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gemini") {
                TextField("Google Cloud 프로젝트 ID", text: $store.geminiProjectID)
                Text("Google Cloud CLI 설치 후 터미널에서 다음 명령을 한 번 실행하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("gcloud auth application-default login")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("새로고침") {
                Picker("주기", selection: $store.refreshIntervalMinutes) {
                    Text("수동").tag(0)
                    Text("5분").tag(5)
                    Text("15분").tag(15)
                    Text("30분").tag(30)
                    Text("60분").tag(60)
                }
            }

            HStack {
                if let message = store.settingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("저장") {
                    store.saveCredentials(openAI: openAIKey, anthropic: anthropicKey)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 500)
        .onAppear {
            guard !didLoad else { return }
            openAIKey = store.storedCredential(for: CredentialAccount.openAI)
            anthropicKey = store.storedCredential(for: CredentialAccount.anthropic)
            didLoad = true
        }
    }
}
