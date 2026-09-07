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

    func consumeResetCredit(
        idempotencyKey: String,
        creditID: String?
    ) async throws -> ResetCreditOutcome {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try consumeResetCreditBlocking(
                        idempotencyKey: idempotencyKey,
                        creditID: creditID
                    )
                })
            }
        }
    }

    private func fetchBlocking() throws -> QuotaSnapshot {
        try Self.parse(performRequest(method: "account/rateLimits/read"))
    }

    private func consumeResetCreditBlocking(
        idempotencyKey: String,
        creditID: String?
    ) throws -> ResetCreditOutcome {
        var params: [String: Any] = ["idempotencyKey": idempotencyKey]
        if let creditID {
            params["creditId"] = creditID
        }
        return try Self.parseResetCreditOutcome(
            performRequest(
                method: "account/rateLimitResetCredit/consume",
                params: params
            )
        )
    }

    private func performRequest(
        method: String,
        params: [String: Any]? = nil
    ) throws -> [String: Any] {
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
        try configureCLIProcess(process, for: "codex")
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
        var sentRequest = false
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

                if id == 1, !sentRequest {
                    sentRequest = true
                    var request: [String: Any] = ["method": method, "id": 2]
                    if let params {
                        request["params"] = params
                    }
                    try write(request, to: input.fileHandleForWriting)
                } else if id == 2 {
                    if let error = object["error"] as? [String: Any] {
                        throw UsageProviderError.commandFailed(
                            error["message"] as? String ?? "Codex 한도를 읽지 못했습니다."
                        )
                    }
                    guard let result = object["result"] as? [String: Any] else {
                        throw UsageProviderError.invalidResponse
                    }
                    return result
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

        var parsedWindows: [(window: QuotaWindow, isNamedLimit: Bool)] = []
        var plan: String?
        for limit in limits {
            plan = plan ?? limit["planType"] as? String
            let limitID = limit["limitId"] as? String ?? "codex"
            let limitName = displayName(for: limit["limitName"] as? String)
            for key in ["primary", "secondary"] {
                guard let window = limit[key] as? [String: Any],
                      let used = number(window["usedPercent"]) else { continue }
                let duration = integer(window["windowDurationMins"])
                let resetSeconds = number(window["resetsAt"])
                let baseTitle = duration.map(windowTitle) ?? "한도"
                let title = [limitName, baseTitle]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                parsedWindows.append((
                    window: QuotaWindow(
                        id: "\(limitID)-\(key)",
                        title: title,
                        kind: (duration ?? 0) >= 10_080 ? .weekly : .shortTerm,
                        usedPercent: used,
                        durationMinutes: duration,
                        resetsAt: resetSeconds.map(Date.init(timeIntervalSince1970:))
                    ),
                    isNamedLimit: limitName != nil
                ))
            }
        }
        guard !parsedWindows.isEmpty else { throw UsageProviderError.invalidResponse }
        parsedWindows.sort { lhs, rhs in
            let lhsRank = windowSortRank(lhs.window, isNamedLimit: lhs.isNamedLimit)
            let rhsRank = windowSortRank(rhs.window, isNamedLimit: rhs.isNamedLimit)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            let lhsDuration = lhs.window.durationMinutes ?? Int.max
            let rhsDuration = rhs.window.durationMinutes ?? Int.max
            if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
            return lhs.window.id < rhs.window.id
        }
        let windows = parsedWindows.map(\.window)
        return QuotaSnapshot(
            provider: .codex,
            windows: windows,
            plan: plan,
            fetchedAt: Date(),
            resetCredits: parseResetCredits(result["rateLimitResetCredits"])
        )
    }

    private static func windowSortRank(
        _ window: QuotaWindow,
        isNamedLimit: Bool
    ) -> Int {
        if isNamedLimit { return 2 }
        return window.kind == .shortTerm ? 0 : 1
    }

    private static func displayName(for rawName: String?) -> String? {
        guard let rawName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return nil
        }

        switch rawName.lowercased() {
        case "gpt-reserve":
            return "예비 한도"
        default:
            return rawName
        }
    }

    static func parseResetCredits(_ value: Any?) -> RateLimitResetCreditsSummary? {
        guard let summary = value as? [String: Any],
              let availableCount = integer(summary["availableCount"]) else {
            return nil
        }

        let credits: [RateLimitResetCredit]?
        if let rows = summary["credits"] as? [[String: Any]] {
            credits = rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let grantedAt = number(row["grantedAt"]),
                      let statusRaw = row["status"] as? String else {
                    return nil
                }
                return RateLimitResetCredit(
                    id: id,
                    title: row["title"] as? String,
                    detail: row["description"] as? String,
                    grantedAt: Date(timeIntervalSince1970: grantedAt),
                    expiresAt: number(row["expiresAt"])
                        .map(Date.init(timeIntervalSince1970:)),
                    status: RateLimitResetCreditStatus(rawValue: statusRaw) ?? .unknown
                )
            }
        } else {
            credits = nil
        }
        return RateLimitResetCreditsSummary(
            availableCount: availableCount,
            credits: credits
        )
    }

    static func parseResetCreditOutcome(
        _ result: [String: Any]
    ) throws -> ResetCreditOutcome {
        guard let rawValue = result["outcome"] as? String,
              let outcome = ResetCreditOutcome(rawValue: rawValue) else {
            throw UsageProviderError.invalidResponse
        }
        return outcome
    }

    private func write(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }
}

func configureCLIProcess(_ process: Process, for command: String) throws {
    let directory = try cliWorkingDirectory(for: command)
    var environment = process.environment ?? ProcessInfo.processInfo.environment
    environment["PWD"] = directory.path
    process.environment = environment
    process.currentDirectoryURL = directory
}

func cliWorkingDirectory(
    for command: String,
    applicationSupportDirectory: URL? = nil,
    fileManager: FileManager = .default
) throws -> URL {
    let supportDirectory: URL
    if let applicationSupportDirectory {
        supportDirectory = applicationSupportDirectory
    } else {
        guard let resolved = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw UsageProviderError.commandFailed(
                "UsageBar 전용 작업 폴더를 찾을 수 없습니다."
            )
        }
        supportDirectory = resolved
    }

    let safeName = command.unicodeScalars.map { scalar in
        CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
    }
    let directory = supportDirectory
        .appendingPathComponent("UsageBar", isDirectory: true)
        .appendingPathComponent("CLIWorkspaces", isDirectory: true)
        .appendingPathComponent(String(safeName), isDirectory: true)
    try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
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

func integer(_ value: Any?) -> Int? {
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
