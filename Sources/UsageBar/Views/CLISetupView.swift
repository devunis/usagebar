import AppKit
import SwiftUI

struct CLISetupView: View {
    @EnvironmentObject private var setup: CLISetupStore
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("사용량 연결하기").font(.title2.bold())
                Text("사용할 서비스의 공식 터미널 프로그램(CLI)을 설치하고 구독 계정으로 로그인해 주세요.")
                    .foregroundStyle(.secondary)
                Text("ChatGPT·Claude 앱만 설치한 경우 CLI는 따로 필요할 수 있어요. 쓰지 않는 서비스는 꺼 두면 됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(CLITool.allCases) { tool in toolCard(tool) }
                }
                .padding(1)
            }
            .scrollBounceBehavior(.basedOnSize)

            if let message = setup.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("자동 설치·로그인은 하지 않습니다. 명령어는 직접 실행하며, 로그인은 각 서비스의 공식 화면에서 진행합니다. API 키는 필요하지 않아요.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("터미널 열기") { setup.openTerminal() }
                Button("설치·사용량 다시 확인") {
                    setup.checkInstallations()
                    store.refreshAll()
                }
                .disabled(!store.refreshingProviders.isEmpty)
                Spacer()
                Button("닫기") { setup.dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 600, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            setup.checkInstallations()
        }
    }

    private func toolCard(_ tool: CLITool) -> some View {
        let executable = setup.installations[tool]
        let enabled = store.isEnabled(tool.provider)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProviderBrandMark(kind: tool.provider)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name).font(.headline)
                    Label(executable == nil ? "CLI 미설치" : "CLI 설치됨",
                          systemImage: executable == nil ? "arrow.down.circle" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(executable == nil ? Color.orange : Color.green)
                }
                Spacer()
                Toggle("사용", isOn: Binding(
                    get: { store.isEnabled(tool.provider) },
                    set: { store.setEnabled($0, for: tool.provider) }
                ))
                .toggleStyle(.switch).fixedSize()
            }

            if !enabled {
                Text("꺼 둔 서비스는 설치하거나 로그인하지 않아도 됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if let executable {
                    Text(executable.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .lineLimit(2).truncationMode(.middle)
                } else {
                    commandStep("1. 공식 CLI 설치", command: tool.installationCommand)
                }
                HStack {
                    Link("공식 설치 안내 ↗", destination: tool.documentationURL)
                    Spacer()
                    Text("설치 후 아래의 ‘다시 확인’을 눌러 주세요.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                commandStep("2. 구독 계정으로 로그인", command: tool.loginCommand(executable: executable),
                            enabled: executable != nil)
                Text(tool == .codex ? "브라우저에서 ChatGPT 계정으로 로그인해 주세요." : "브라우저에서 Claude 구독 계정으로 로그인해 주세요. Console/API 키 로그인이 아닙니다.")
                    .font(.caption).foregroundStyle(.secondary)
                usageStatus(tool)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func commandStep(_ title: String, command: String, enabled: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Button("복사") { setup.copy(command) }.font(.caption).disabled(!enabled)
            }
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(enabled ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func usageStatus(_ tool: CLITool) -> some View {
        if store.isRefreshing(tool.provider) {
            HStack { ProgressView().controlSize(.small); Text("3. 사용량 확인 중…") }.font(.caption)
        } else if case .loaded = store.states[tool.provider] {
            Label("3. 사용량 조회 이력 있음 · 최신 상태는 메뉴바에서 확인", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("3. 로그인 후 ‘설치·사용량 다시 확인’을 눌러 연결을 확인하세요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
