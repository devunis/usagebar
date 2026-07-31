import Foundation

struct HTTPClient: Sendable {
    var session: URLSession = .shared

    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageProviderError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "응답 본문 없음"
            if http.statusCode == 401 || http.statusCode == 403 {
                throw UsageProviderError.unauthorized("인증 정보 또는 권한을 확인해 주세요. (\(http.statusCode))")
            }
            throw UsageProviderError.server(status: http.statusCode, message: body)
        }

        return data
    }
}
