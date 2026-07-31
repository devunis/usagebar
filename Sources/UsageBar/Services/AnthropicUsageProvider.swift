import Foundation

struct AnthropicUsageProvider: UsageProvider {
    let kind = ProviderKind.anthropic
    let keychain: KeychainStore
    let client: HTTPClient

    init(keychain: KeychainStore = .shared, client: HTTPClient = HTTPClient()) {
        self.keychain = keychain
        self.client = client
    }

    func fetchUsage(from start: Date, to end: Date) async throws -> UsageSnapshot {
        guard let adminKey = keychain.value(for: CredentialAccount.anthropic),
              !adminKey.isEmpty else {
            throw UsageProviderError.missingCredential("Anthropic Admin API 키가 필요합니다.")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")
        components?.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: start)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]
        guard let url = components?.url else { throw UsageProviderError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await client.data(for: request)
        let page = try JSONDecoder().decode(AnthropicUsagePage.self, from: data)
        let results = page.data.flatMap(\.results)
        let input = results.reduce(0) {
            $0 + $1.uncachedInputTokens + $1.cacheReadInputTokens + $1.cacheCreation.total
        }

        return UsageSnapshot(
            provider: kind,
            inputTokens: input,
            outputTokens: results.reduce(0) { $0 + $1.outputTokens },
            requests: results.reduce(0) { $0 + $1.requests },
            periodStart: start,
            periodEnd: end,
            fetchedAt: Date()
        )
    }
}

struct AnthropicUsagePage: Decodable {
    let data: [Bucket]

    struct Bucket: Decodable {
        let results: [Result]
    }

    struct Result: Decodable {
        let uncachedInputTokens: Int
        let cacheReadInputTokens: Int
        let cacheCreation: CacheCreation
        let outputTokens: Int
        let requests: Int

        enum CodingKeys: String, CodingKey {
            case uncachedInputTokens = "uncached_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreation = "cache_creation"
            case outputTokens = "output_tokens"
            case requests
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            uncachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .uncachedInputTokens) ?? 0
            cacheReadInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
            cacheCreation = try container.decodeIfPresent(CacheCreation.self, forKey: .cacheCreation) ?? CacheCreation()
            outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
            requests = try container.decodeIfPresent(Int.self, forKey: .requests) ?? 0
        }
    }

    struct CacheCreation: Decodable {
        let ephemeral1hInputTokens: Int
        let ephemeral5mInputTokens: Int

        var total: Int { ephemeral1hInputTokens + ephemeral5mInputTokens }

        enum CodingKeys: String, CodingKey {
            case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
            case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        }

        init(ephemeral1hInputTokens: Int = 0, ephemeral5mInputTokens: Int = 0) {
            self.ephemeral1hInputTokens = ephemeral1hInputTokens
            self.ephemeral5mInputTokens = ephemeral5mInputTokens
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ephemeral1hInputTokens = try container.decodeIfPresent(Int.self, forKey: .ephemeral1hInputTokens) ?? 0
            ephemeral5mInputTokens = try container.decodeIfPresent(Int.self, forKey: .ephemeral5mInputTokens) ?? 0
        }
    }
}
