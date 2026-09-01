import Foundation

/// The one HTTP primitive the core needs, so tests can script responses without touching the network.
public protocol Transport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: Transport {}
