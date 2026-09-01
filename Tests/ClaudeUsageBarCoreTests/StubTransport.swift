import Foundation
@testable import ClaudeUsageBarCore

/// Scripted HTTP responses, served in order; records every request for assertions.
actor StubTransport: Transport {
    struct Response {
        let status: Int
        let body: String
        var headers: [String: String] = [:]

        static func ok(_ body: String) -> Response { Response(status: 200, body: body) }
    }

    struct UnexpectedRequest: Error {}

    private var queue: [Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Response]) {
        queue = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !queue.isEmpty else { throw UnexpectedRequest() }
        let next = queue.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: next.headers)!
        return (Data(next.body.utf8), response)
    }
}
