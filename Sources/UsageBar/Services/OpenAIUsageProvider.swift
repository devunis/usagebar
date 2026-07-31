import Foundation

struct CodexQuotaProvider: QuotaProvider {
    let kind = ProviderKind.codex

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
        process.executableURL = try executableURL(named: "codex", candidates: [
            "~/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ])
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw UsageProviderError.commandFailed("Codex CLI를 실행할 수 없습니다.")
        }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        try write([
            "method": "initialize",
            "id": 1,
            "params": [
                "clientInfo": [
                    "name": "usagebar",
                    "title": "UsageBar",
                    "version": Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String ?? "development"
                ],
                "capabilities": [:]
            ]
        ], to: input.fileHandleForWriting)

        var buffer = Data()
        var sentRateRequest = false
        while process.isRunning {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let id = object["id"] as? Int else {
                    continue
                }

                if id == 1, !sentRateRequest {
                    sentRateRequest = true
                    try write(
                        ["method": "account/rateLimits/read", "id": 2],
                        to: input.fileHandleForWriting
                    )
                } else if id == 2 {
                    if let error = object["error"] as? [String: Any] {
                        throw UsageProviderError.commandFailed(
                            error["message"] as? String ?? "Codex 한도를 읽지 못했습니다."
                        )
                    }
                    guard let result = object["result"] as? [String: Any] else {
                        throw UsageProviderError.invalidResponse
                    }
                    return try Self.parse(result)
                }
            }
        }

        let detail = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw UsageProviderError.commandFailed(
            detail?.isEmpty == false ? detail! : "Codex CLI 로그인이 필요합니다."
        )
    }

    static func parse(_ result: [String: Any]) throws -> QuotaSnapshot {
        var limits: [[String: Any]] = []
        if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            limits = byID.values.compactMap { $0 as? [String: Any] }
        }
        if limits.isEmpty, let limit = result["rateLimits"] as? [String: Any] {
            limits = [limit]
        }

        var windows: [QuotaWindow] = []
        var plan: String?
        for limit in limits {
            plan = plan ?? limit["planType"] as? String
            let limitID = limit["limitId"] as? String ?? "codex"
            let limitName = limit["limitName"] as? String
            for (key, suffix) in [("primary", ""), ("secondary", " 보조")] {
                guard let window = limit[key] as? [String: Any],
                      let used = number(window["usedPercent"]) else { continue }
                let duration = integer(window["windowDurationMins"])
                let resetSeconds = number(window["resetsAt"])
                let baseTitle = duration.map(windowTitle) ?? "한도"
                let title = [limitName, baseTitle + suffix]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                windows.append(QuotaWindow(
                    id: "\(limitID)-\(key)",
                    title: title,
                    kind: (duration ?? 0) >= 10_080 ? .weekly : .shortTerm,
                    usedPercent: used,
                    durationMinutes: duration,
                    resetsAt: resetSeconds.map(Date.init(timeIntervalSince1970:))
                ))
            }
        }
        guard !windows.isEmpty else { throw UsageProviderError.invalidResponse }
        windows.sort { ($0.durationMinutes ?? 0) > ($1.durationMinutes ?? 0) }
        return QuotaSnapshot(
            provider: .codex,
            windows: windows,
            plan: plan,
            fetchedAt: Date()
        )
    }

    private func write(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }
}

func executableURL(named name: String, candidates: [String]) throws -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let expanded = candidates.map {
        $0.hasPrefix("~/") ? home + "/" + $0.dropFirst(2) : $0
    }
    if let path = expanded.first(where: FileManager.default.isExecutableFile) {
        return URL(fileURLWithPath: path)
    }
    let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
        .split(separator: ":").map(String.init) ?? []
    if let path = pathEntries
        .map({ URL(fileURLWithPath: $0).appendingPathComponent(name).path })
        .first(where: FileManager.default.isExecutableFile) {
        return URL(fileURLWithPath: path)
    }
    throw UsageProviderError.missingCredential("\(name) CLI를 설치하고 로그인해 주세요.")
}

func number(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String { return Double(string) }
    return nil
}

private func integer(_ value: Any?) -> Int? {
    number(value).map(Int.init)
}

func windowTitle(_ minutes: Int) -> String {
    switch minutes {
    case 10_080...: "주간"
    case 1_440...: "\(minutes / 1_440)일"
    case 60...: "\(minutes / 60)시간"
    default: "\(minutes)분"
    }
}
