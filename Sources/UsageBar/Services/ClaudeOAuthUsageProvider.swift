import Foundation
import Security
import LocalAuthentication

enum ClaudeOAuthUsageProvider {
    static func accessTokenWithoutPrompt() -> String? {
        accessToken(allowAuthenticationUI: false)
    }

    static func readAccessTokenWithoutPrompt() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: accessTokenWithoutPrompt())
            }
        }
    }

    static func connectOnUserAction() async throws -> QuotaSnapshot {
        let token: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: accessToken(allowAuthenticationUI: true))
            }
        }
        guard let token else {
            throw UsageProviderError.credentialAccessRequired("Claude 로그인 정보에 접근할 수 없습니다. ‘다시 연결’을 눌러 주세요.")
        }
        return try await fetchQuota(accessToken: token)
    }

    private static func accessToken(allowAuthenticationUI: Bool) -> String? {
        let customDirectory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .flatMap { $0.isEmpty ? nil : $0 }
        let directory = customDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let credentialsFile = directory.appendingPathComponent(".credentials.json")
        if let data = try? Data(contentsOf: credentialsFile),
           let token = accessToken(in: data) {
            return token
        }

        // Do not substitute another account's default Keychain item for a custom profile.
        guard customDirectory == nil else { return nil }
        let context = LAContext()
        context.interactionNotAllowed = !allowAuthenticationUI
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            // Also set the process-wide legacy policy in ClaudeKeychainAccess below.
            kSecUseAuthenticationUI as String: allowAuthenticationUI
                ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        ]
        guard let data: Data = ClaudeKeychainAccess.withInteractionPolicy(
            allowAuthenticationUI: allowAuthenticationUI,
            operation: {
                var result: CFTypeRef?
                guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
                return result as? Data
            }
        ) else { return nil }
        return accessToken(in: data)
    }

    private static func accessToken(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return nil
        }
        if let expiresAt = number(oauth["expiresAt"]),
           expiresAt / 1000 <= Date().timeIntervalSince1970 {
            return nil
        }
        return token
    }

    static func fetchQuota(accessToken: String) async throws -> QuotaSnapshot {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        // These optional benefit fields come from Claude's own usage endpoint.
        // Fall back to ordinary usage if the server rejects the optional query.
        for includeResets in [true, false] {
            let suffix = includeResets ? "?cedar_ember=1" : ""
            let url = URL(string: "https://api.anthropic.com/api/oauth/usage\(suffix)")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw UsageProviderError.invalidResponse
            }
            if includeResets && [400, 403].contains(response.statusCode) { continue }
            if [401, 403].contains(response.statusCode) {
                throw UsageProviderError.credentialAccessRequired("Claude 로그인을 확인한 뒤 ‘다시 연결’을 눌러 주세요.")
            }
            guard response.statusCode == 200 else {
                throw UsageProviderError.server(status: response.statusCode, message: "Claude 추가 정보 조회를 완료하지 못했습니다.")
            }
            guard data.count <= 1_000_000,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UsageProviderError.invalidResponse
            }
            return try parse(root)
        }
        throw UsageProviderError.invalidResponse
    }

    private static var userAgent: String {
        if let executable = try? executableURL(named: "claude", candidates: [
            "~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"
        ]) {
            let version = executable.resolvingSymlinksInPath()
                .deletingLastPathComponent().lastPathComponent
            if version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil {
                return "claude-cli/\(version) (external, cli)"
            }
        }
        return "UsageBar"
    }

    static func parse(_ root: [String: Any], now: Date = Date()) throws -> QuotaSnapshot {
        var windows: [QuotaWindow] = []
        let definitions: [(String, String, QuotaWindowKind, Int)] = [
            ("five_hour", "5시간", .shortTerm, 300),
            ("seven_day", "주간", .weekly, 10_080)
        ]
        for (key, title, kind, duration) in definitions {
            if let window = parseWindow(root[key], id: key, title: title, kind: kind, duration: duration) {
                windows.append(window)
            }
        }
        for key in root.keys.sorted() where key.hasPrefix("seven_day_") {
            let scope = key.replacingOccurrences(of: "seven_day_", with: "")
            let title = scope.replacingOccurrences(of: "_", with: " ").capitalized + " 주간"
            if let window = parseWindow(root[key], id: key, title: title, kind: .modelScoped, duration: 10_080) {
                windows.append(window)
            }
        }
        guard !windows.isEmpty else { throw UsageProviderError.invalidResponse }
        return QuotaSnapshot(
            provider: .anthropic,
            windows: windows,
            plan: nil,
            fetchedAt: now,
            claudeBenefits: ClaudeAccountBenefits(
                resets: parseResets(root["cedar_ember"]),
                cloudCredits: parseCloudCredits(root["iguana_necktie"]),
                unavailableMessage: nil
            )
        )
    }

    private static func parseWindow(
        _ value: Any?, id: String, title: String, kind: QuotaWindowKind, duration: Int
    ) -> QuotaWindow? {
        guard let window = value as? [String: Any],
              let used = finiteNumber(window["utilization"]), (0...100).contains(used) else { return nil }
        return QuotaWindow(
            id: id, title: title, kind: kind, usedPercent: used,
            durationMinutes: duration, resetsAt: date(window["resets_at"])
        )
    }

    static func parseResets(_ value: Any?) -> ClaudeResetInventory? {
        guard let block = value as? [String: Any], block["eligible"] as? Bool == true,
              let rows = block["grants"] as? [[String: Any]], rows.count <= 200 else { return nil }
        var grants: [ClaudeResetGrant] = []
        for row in rows {
            guard let left = finiteNumber(row["resets_left"]),
                  let total = finiteNumber(row["resets_total"]),
                  left.rounded() == left, total.rounded() == total,
                  (0...50).contains(left), left <= total, total <= 50,
                  let paused = row["paused"] as? Bool,
                  let start = date(row["starts_at"]), let end = date(row["ends_at"]), start < end else {
                // Do not turn an unknown inventory into "no resets".
                return nil
            }
            grants.append(ClaudeResetGrant(remaining: Int(left), startsAt: start, expiresAt: end, paused: paused))
        }
        guard grants.reduce(0, { $0 + $1.remaining }) <= 50 else { return nil }
        return ClaudeResetInventory(grants: grants)
    }

    static func parseCloudCredits(_ value: Any?) -> ClaudeCloudCredits? {
        guard let block = value as? [String: Any],
              let allowance = finiteNumber(block["limit_dollars"]), allowance > 0 else { return nil }
        let remaining: Double
        if let reported = finiteNumber(block["remaining_dollars"]) {
            remaining = reported
        } else if let used = finiteNumber(block["used_dollars"]) {
            remaining = allowance - used
        } else if let utilization = finiteNumber(block["utilization"]) {
            remaining = allowance * (1 - utilization / 100)
        } else {
            return nil
        }
        return ClaudeCloudCredits(
            allowanceUSD: allowance, remainingUSD: min(allowance, max(0, remaining)),
            expiresAt: date(block["resets_at"]), locked: block["is_locked"] as? Bool ?? false
        )
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { return nil }
        guard let numeric = number(value), numeric.isFinite else { return nil }
        return numeric
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = finiteNumber(value) {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
        }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
