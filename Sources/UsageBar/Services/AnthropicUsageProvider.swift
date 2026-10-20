import Foundation

struct ClaudeQuotaProvider: QuotaProvider {
    let kind = ProviderKind.anthropic
    var loadCLI: @Sendable () async throws -> QuotaSnapshot = {
        try await ClaudeCLIUsageProvider().fetchQuota()
    }
    var readToken: @Sendable () async throws -> String? = {
        try await ClaudeOAuthUsageProvider.readAccessTokenWithoutPrompt()
    }
    var loadQuota: @Sendable (String) async throws -> QuotaSnapshot = {
        try await ClaudeOAuthUsageProvider.fetchQuota(accessToken: $0)
    }

    func fetchQuota() async throws -> QuotaSnapshot {
        // Let the credential owner handle authentication first. Do not touch the
        // foreign Keychain item at all when Claude Code supplies usable quotas.
        do { return try await loadCLI() }
        catch is CancellationError { throw CancellationError() }
        catch { /* Missing/old/unavailable CLI: try the noninteractive fallback. */ }
        try Task.checkCancellation()
        guard let token = try await readToken() else {
            throw UsageProviderError.credentialAccessRequired("Claude Code CLI 설치·로그인 상태를 확인해 주세요. 기존 로그인 정보를 통한 대체 조회도 사용할 수 없습니다.")
        }
        return try await loadQuota(token)
    }

    static func parseCLIResult(_ data: Data) throws -> QuotaSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["is_error"] as? Bool != true,
              let result = object["result"] as? String else {
            throw UsageProviderError.invalidResponse
        }
        return try parseCLIUsage(result)
    }

    static func parseCLIUsage(_ text: String, now: Date = Date()) throws -> QuotaSnapshot {
        let cleaned = removingANSISequences(from: text)
        let lines = cleaned.components(separatedBy: .newlines)
        var windows: [QuotaWindow] = []

        for (index, line) in lines.enumerated() {
            guard let definition = windowDefinition(for: line) else { continue }
            let nextHeader = lines[(index + 1)...].firstIndex {
                windowDefinition(for: $0) != nil
            } ?? lines.endIndex
            let detailLines = lines[(index + 1)..<nextHeader]
            guard let percent = percentUsed(in: line) ?? detailLines
                .compactMap({ percentUsed(in: $0) }).first else {
                continue
            }
            let resetLine = line.localizedCaseInsensitiveContains("reset")
                ? line
                : detailLines.first { $0.localizedCaseInsensitiveContains("reset") }
            let reset = resetLine
                .flatMap(resetDate)

            windows.append(QuotaWindow(
                id: definition.id,
                title: definition.title,
                kind: definition.kind,
                usedPercent: percent,
                durationMinutes: definition.durationMinutes,
                resetsAt: reset
            ))
        }

        guard !windows.isEmpty else {
            throw UsageProviderError.missingCredential(
                "Claude CLI에 로그인해 주세요: claude auth login"
            )
        }
        return QuotaSnapshot(
            provider: .anthropic,
            windows: windows,
            plan: nil,
            fetchedAt: now,
            claudeBenefits: .unavailable
        )
    }

    private static func windowDefinition(
        for line: String
    ) -> (id: String, title: String, kind: QuotaWindowKind, durationMinutes: Int)? {
        let fullLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = fullLine
            .split(separator: ":", maxSplits: 1)
            .first
            .map(String.init) ?? fullLine
        let normalized = title.lowercased()
        if normalized == "current session" {
            return ("five_hour", "5시간", .shortTerm, 300)
        }
        guard normalized.hasPrefix("current week") else { return nil }

        if normalized.contains("all models") || !normalized.contains("(") {
            return ("seven_day", "주간", .weekly, 10_080)
        }

        let scope = title
            .split(separator: "(", maxSplits: 1)
            .last?
            .trimmingCharacters(in: CharacterSet(charactersIn: ") ")) ?? "Model"
        let identifier = scope.lowercased().map {
            $0.isLetter || $0.isNumber ? $0 : "-"
        }.reduce(into: "") { $0.append($1) }
        return ("weekly-scoped-\(identifier)", "\(scope) 주간", .modelScoped, 10_080)
    }

    private static func percentUsed(in line: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*%\s*used"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              let percentRange = Range(match.range(at: 1), in: line) else { return nil }
        return Double(line[percentRange])
    }

    private static func resetDate(from line: String) -> Date? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return detector.matches(in: line, range: range).first?.date
    }

    private static func removingANSISequences(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\u{001B}\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }
}
