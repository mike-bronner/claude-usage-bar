import Foundation

public enum UsageError: Error {
    case unauthorized
    /// The endpoint throttled us; `retryAfter` is the server's `Retry-After` in seconds, if given.
    case rateLimited(retryAfter: TimeInterval?)
    case transport(any Error)
    case unexpectedStatus(Int)
    case malformedResponse
}

/// Fetches plan usage from the OAuth usage endpoint Claude Code itself calls.
public struct UsageClient: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let transport: any Transport

    public init(transport: any Transport = URLSession.shared) {
        self.transport = transport
    }

    /// Returns the raw response body. Callers decode; the shape is captured by `usage-probe`.
    public func fetchRaw(accessToken: String) async throws -> Data {
        let (http, data) = try await fetchResponse(accessToken: accessToken)
        switch http.statusCode {
        case 200: return data
        case 401, 403: throw UsageError.unauthorized
        case 429: throw UsageError.rateLimited(retryAfter: Self.retryAfter(http))
        default: throw UsageError.unexpectedStatus(http.statusCode)
        }
    }

    /// The unjudged response, for diagnostics: `usage-probe` prints headers and body on a failure.
    public func fetchResponse(accessToken: String) async throws -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data, response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw UsageError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw UsageError.unexpectedStatus(-1) }
        return (http, data)
    }

    /// Only the delay-seconds form of `Retry-After`. An HTTP-date, or a non-positive value (the
    /// endpoint sends `0` while still refusing), is treated as absent.
    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init),
              seconds > 0
        else { return nil }
        return seconds
    }
}
