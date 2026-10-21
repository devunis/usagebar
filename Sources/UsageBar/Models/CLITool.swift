import Foundation

enum CLITool: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    var id: String { rawValue }
    var provider: ProviderKind { self == .codex ? .codex : .anthropic }
    var name: String { self == .codex ? "Codex CLI" : "Claude Code CLI" }
    var candidates: [String] {
        ["~/.local/bin/\(rawValue)", "/opt/homebrew/bin/\(rawValue)", "/usr/local/bin/\(rawValue)"]
    }
    var installationCommand: String {
        switch self {
        case .codex: "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
        case .claude: "curl -fsSL https://claude.ai/install.sh | bash"
        }
    }
    var documentationURL: URL {
        switch self {
        case .codex: URL(string: "https://learn.chatgpt.com/docs/codex/cli#getting-started")!
        case .claude: URL(string: "https://code.claude.com/docs/en/setup#install-claude-code")!
        }
    }
    var loginArguments: String { self == .codex ? "login" : "auth login" }

    func resolveExecutable() throws -> URL {
        try executableURL(named: rawValue, candidates: candidates)
    }

    func loginCommand(executable: URL?) -> String {
        // GUI apps and Terminal may have different PATHs. Quote the exact detected
        // path so spaces/apostrophes cannot turn it into another shell command.
        let command = executable.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" } ?? rawValue
        return "\(command) \(loginArguments)"
    }
}

func shouldOfferCLISetup(
    hasSeenGuide: Bool, enabledProviders: Set<ProviderKind>, installedTools: Set<CLITool>
) -> Bool {
    !hasSeenGuide && CLITool.allCases.contains {
        enabledProviders.contains($0.provider) && !installedTools.contains($0)
    }
}
