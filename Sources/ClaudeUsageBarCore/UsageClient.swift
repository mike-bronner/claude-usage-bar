import Foundation

public enum UsageError: Error {
    case unauthorized
    case transport(any Error)
    case unexpectedStatus(Int)
}

/// Fetches plan usage from the OAuth usage endpoint Claude Code itself calls.
public struct UsageClient: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns the raw response body. Callers decode; the shape is captured by `usage-probe`.
    public func fetchRaw(accessToken: String) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else { throw UsageError.unexpectedStatus(-1) }
        switch http.statusCode {
        case 200: return data
        case 401, 403: throw UsageError.unauthorized
        default: throw UsageError.unexpectedStatus(http.statusCode)
        }
    }
}
