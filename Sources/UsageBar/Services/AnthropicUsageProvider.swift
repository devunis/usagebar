import Foundation
import Security

struct ClaudeQuotaProvider: QuotaProvider {
    let kind = ProviderKind.anthropic
    let client: HTTPClient

    init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    func fetchQuota() async throws -> QuotaSnapshot {
        guard let token = Self.oauthToken() else {
            throw UsageProviderError.missingCredential(
                "Claude CLI 로그인이 필요합니다: claude auth login"
            )
        }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw UsageProviderError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let data = try await client.data(for: request)
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> QuotaSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageProviderError.invalidResponse
        }
        let definitions = [
            ("five_hour", "5시간"),
            ("seven_day", "주간"),
            ("seven_day_sonnet", "Sonnet 주간"),
            ("seven_day_opus", "Opus 주간")
        ]
        let formatter = ISO8601DateFormatter()
        let windows = definitions.compactMap { key, title -> QuotaWindow? in
            guard let value = object[key] as? [String: Any],
                  let utilization = number(value["utilization"]) else { return nil }
            let reset = (value["resets_at"] as? String).flatMap(formatter.date)
            return QuotaWindow(
                id: key,
                title: title,
                usedPercent: utilization,
                durationMinutes: key == "five_hour" ? 300 : 10_080,
                resetsAt: reset
            )
        }
        guard !windows.isEmpty else { throw UsageProviderError.invalidResponse }
        return QuotaSnapshot(
            provider: .anthropic,
            windows: windows,
            plan: nil,
            fetchedAt: Date()
        )
    }

    private static func oauthToken() -> String? {
        let credentials = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: credentials),
           let token = token(from: data) {
            return token
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            return token(from: data)
        }
        return nil
    }

    private static func token(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }
}
