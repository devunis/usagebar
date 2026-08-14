import Foundation

struct ClaudeQuotaProvider: QuotaProvider {
    let kind = ProviderKind.anthropic

    func fetchQuota() async throws -> QuotaSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try fetchBlocking() })
            }
        }
    }

    private func fetchBlocking() throws -> QuotaSnapshot {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = try executableURL(named: "claude", candidates: [
            "~/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ])
        process.arguments = [
            "--safe-mode",
            "-p",
            "--no-session-persistence",
            "--output-format", "json",
            "/usage"
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            try input.fileHandleForWriting.close()
        } catch {
            throw UsageProviderError.commandFailed("Claude CLI를 실행할 수 없습니다.")
        }

        if finished.wait(timeout: .now() + 15) == .timedOut {
            process.terminate()
            throw UsageProviderError.commandFailed("Claude 사용량 조회 시간이 초과되었습니다.")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw UsageProviderError.missingCredential(
                errorText?.isEmpty == false
                    ? errorText!
                    : "Claude CLI에 로그인해 주세요: claude auth login"
            )
        }
        return try Self.parseCLIResult(data)
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
            fetchedAt: now
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
