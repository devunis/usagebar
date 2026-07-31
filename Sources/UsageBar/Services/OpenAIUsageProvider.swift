import Foundation

struct OpenAIUsageProvider: UsageProvider {
    let kind = ProviderKind.openAI
    let keychain: KeychainStore
    let client: HTTPClient

    init(keychain: KeychainStore = .shared, client: HTTPClient = HTTPClient()) {
        self.keychain = keychain
        self.client = client
    }

    func fetchUsage(from start: Date, to end: Date) async throws -> UsageSnapshot {
        guard let adminKey = keychain.value(for: CredentialAccount.openAI),
              !adminKey.isEmpty else {
            throw UsageProviderError.missingCredential("OpenAI Admin API 키가 필요합니다.")
        }

        var components = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")
        components?.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int(end.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]
        guard let url = components?.url else { throw UsageProviderError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await client.data(for: request)
        let page = try JSONDecoder().decode(OpenAIUsagePage.self, from: data)
        let results = page.data.flatMap(\.results)

        return UsageSnapshot(
            provider: kind,
            inputTokens: results.reduce(0) { $0 + $1.inputTokens },
            outputTokens: results.reduce(0) { $0 + $1.outputTokens },
            requests: results.reduce(0) { $0 + $1.numModelRequests },
            periodStart: start,
            periodEnd: end,
            fetchedAt: Date()
        )
    }
}

struct OpenAIUsagePage: Decodable {
    let data: [Bucket]

    struct Bucket: Decodable {
        let results: [Result]
    }

    struct Result: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        let numModelRequests: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case numModelRequests = "num_model_requests"
        }
    }
}
