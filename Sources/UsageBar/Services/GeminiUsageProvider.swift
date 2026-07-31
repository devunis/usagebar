import Foundation

struct GeminiUsageProvider: UsageProvider {
    let kind = ProviderKind.gemini
    let projectID: String
    let client: HTTPClient
    let tokenProvider: GCloudTokenProvider

    init(
        projectID: String,
        client: HTTPClient = HTTPClient(),
        tokenProvider: GCloudTokenProvider = GCloudTokenProvider()
    ) {
        self.projectID = projectID
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func fetchUsage(from start: Date, to end: Date) async throws -> UsageSnapshot {
        let project = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else {
            throw UsageProviderError.missingCredential("Google Cloud 프로젝트 ID가 필요합니다.")
        }
        let accessToken = try tokenProvider.accessToken()

        async let freeInput = metric(
            "generativelanguage.googleapis.com/quota/generate_content_free_tier_input_token_count/usage",
            project: project, token: accessToken, start: start, end: end
        )
        async let paidInput = metric(
            "generativelanguage.googleapis.com/quota/generate_content_paid_tier_input_token_count/usage",
            project: project, token: accessToken, start: start, end: end
        )
        async let output = metric(
            "generativelanguage.googleapis.com/generate_content_usage_output_token_count",
            project: project, token: accessToken, start: start, end: end
        )
        async let freeRequests = metric(
            "generativelanguage.googleapis.com/quota/generate_content_free_tier_requests/usage",
            project: project, token: accessToken, start: start, end: end
        )
        async let paidRequests = metric(
            "generativelanguage.googleapis.com/quota/generate_requests_per_model/usage",
            project: project, token: accessToken, start: start, end: end
        )

        return try await UsageSnapshot(
            provider: kind,
            inputTokens: freeInput + paidInput,
            outputTokens: output,
            requests: freeRequests + paidRequests,
            periodStart: start,
            periodEnd: end,
            fetchedAt: Date()
        )
    }

    private func metric(
        _ type: String,
        project: String,
        token: String,
        start: Date,
        end: Date
    ) async throws -> Int {
        var components = URLComponents(
            string: "https://monitoring.googleapis.com/v3/projects/\(project)/timeSeries"
        )
        let formatter = ISO8601DateFormatter()
        components?.queryItems = [
            URLQueryItem(name: "filter", value: "metric.type=\"\(type)\""),
            URLQueryItem(name: "interval.startTime", value: formatter.string(from: start)),
            URLQueryItem(name: "interval.endTime", value: formatter.string(from: end)),
            URLQueryItem(name: "view", value: "FULL")
        ]
        guard let url = components?.url else { throw UsageProviderError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await client.data(for: request)
        let response = try JSONDecoder().decode(MonitoringResponse.self, from: data)
        return response.timeSeries.reduce(0) { seriesTotal, series in
            seriesTotal + series.points.reduce(0) { $0 + $1.value.integer }
        }
    }
}

struct GCloudTokenProvider: Sendable {
    func accessToken() throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = try executableURL()
        process.arguments = ["auth", "application-default", "print-access-token"]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw UsageProviderError.commandFailed(
                "gcloud를 찾을 수 없습니다. Google Cloud CLI를 설치해 주세요."
            )
        }
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let token = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            let detail = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw UsageProviderError.commandFailed(
                detail?.isEmpty == false
                    ? detail!
                    : "먼저 gcloud auth application-default login을 실행해 주세요."
            )
        }
        return token
    }

    private func executableURL() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/gcloud",
            "/usr/local/bin/gcloud",
            "\(home)/google-cloud-sdk/bin/gcloud",
            "\(home)/.local/google-cloud-sdk/bin/gcloud"
        ]

        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        let environmentPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        if let path = environmentPaths
            .map({ URL(fileURLWithPath: $0).appendingPathComponent("gcloud").path })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        throw UsageProviderError.commandFailed(
            "gcloud를 찾을 수 없습니다. Google Cloud CLI를 설치해 주세요."
        )
    }
}

struct MonitoringResponse: Decodable {
    let timeSeries: [TimeSeries]

    enum CodingKeys: String, CodingKey {
        case timeSeries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeSeries = try container.decodeIfPresent([TimeSeries].self, forKey: .timeSeries) ?? []
    }

    struct TimeSeries: Decodable {
        let points: [Point]
    }

    struct Point: Decodable {
        let value: TypedValue
    }

    struct TypedValue: Decodable {
        let int64Value: String?
        let doubleValue: Double?

        var integer: Int {
            if let int64Value, let value = Int(int64Value) { return value }
            if let doubleValue { return Int(doubleValue) }
            return 0
        }
    }
}

enum CredentialAccount {
    static let openAI = "openai-admin-key"
    static let anthropic = "anthropic-admin-key"
}
