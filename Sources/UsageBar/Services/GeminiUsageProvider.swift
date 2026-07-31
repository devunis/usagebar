import Foundation

struct GeminiQuotaProvider: QuotaProvider {
    let kind = ProviderKind.gemini
    let client: HTTPClient

    init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    func fetchQuota() async throws -> QuotaSnapshot {
        let credentialsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
        guard let credentialsData = try? Data(contentsOf: credentialsURL),
              let credentials = try? JSONSerialization.jsonObject(with: credentialsData)
                as? [String: Any],
              let token = credentials["access_token"] as? String,
              !token.isEmpty else {
            throw UsageProviderError.missingCredential(
                "Gemini CLI를 설치하고 Google 계정으로 로그인해 주세요."
            )
        }
        if let expiry = number(credentials["expiry_date"]),
           Date(timeIntervalSince1970: expiry / 1_000) <= Date() {
            throw UsageProviderError.missingCredential(
                "Gemini CLI 로그인이 만료되었습니다. gemini를 실행해 다시 로그인해 주세요."
            )
        }

        let loadData = try await post(
            endpoint: "v1internal:loadCodeAssist",
            token: token,
            body: ["metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]]
        )
        guard let load = try JSONSerialization.jsonObject(with: loadData) as? [String: Any] else {
            throw UsageProviderError.invalidResponse
        }
        let project: String? = {
            if let value = load["cloudaicompanionProject"] as? String { return value }
            if let value = load["cloudaicompanionProject"] as? [String: Any] {
                return value["id"] as? String ?? value["projectId"] as? String
            }
            return nil
        }()
        var body: [String: Any] = [:]
        if let project, !project.isEmpty { body["project"] = project }

        let quotaData = try await post(
            endpoint: "v1internal:retrieveUserQuota",
            token: token,
            body: body
        )
        return try Self.parse(quotaData, plan: load["paidTier"] as? String)
    }

    private func post(
        endpoint: String,
        token: String,
        body: [String: Any]
    ) async throws -> Data {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/\(endpoint)") else {
            throw UsageProviderError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await client.data(for: request)
    }

    static func parse(_ data: Data, plan: String? = nil) throws -> QuotaSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = object["buckets"] as? [[String: Any]] else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            if detail.localizedCaseInsensitiveContains("ineligible") ||
                detail.localizedCaseInsensitiveContains("unsupported") {
                throw UsageProviderError.unsupported(
                    "이 Gemini 계정 유형은 CLI 한도 조회를 지원하지 않습니다."
                )
            }
            throw UsageProviderError.invalidResponse
        }

        var byModel: [String: (remaining: Double, reset: Date?)] = [:]
        let formatter = ISO8601DateFormatter()
        for bucket in buckets {
            guard let remaining = number(bucket["remainingFraction"]) else { continue }
            let model = bucket["modelId"] as? String ?? "Gemini"
            let reset = (bucket["resetTime"] as? String).flatMap(formatter.date)
            if let current = byModel[model], current.remaining <= remaining { continue }
            byModel[model] = (remaining, reset)
        }
        let windows = byModel.map { model, value in
            QuotaWindow(
                id: model,
                title: model.replacingOccurrences(of: "gemini-", with: "Gemini "),
                kind: .modelScoped,
                usedPercent: (1 - value.remaining) * 100,
                durationMinutes: nil,
                resetsAt: value.reset
            )
        }.sorted { $0.title < $1.title }
        guard !windows.isEmpty else { throw UsageProviderError.invalidResponse }
        return QuotaSnapshot(
            provider: .gemini,
            windows: windows,
            plan: plan,
            fetchedAt: Date()
        )
    }
}
