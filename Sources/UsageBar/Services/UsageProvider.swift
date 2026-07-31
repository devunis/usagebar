import Foundation

protocol QuotaProvider: Sendable {
    var kind: ProviderKind { get }
    func fetchQuota() async throws -> QuotaSnapshot
}

enum UsageProviderError: LocalizedError {
    case missingCredential(String)
    case invalidURL
    case invalidResponse
    case unauthorized(String)
    case server(status: Int, message: String)
    case commandFailed(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let message):
            message
        case .invalidURL:
            "요청 URL을 만들 수 없습니다."
        case .invalidResponse:
            "서버 응답을 해석할 수 없습니다."
        case .unauthorized(let message):
            message
        case .server(let status, let message):
            "서버 오류 \(status): \(message)"
        case .commandFailed(let message):
            message
        case .unsupported(let message):
            message
        }
    }
}
