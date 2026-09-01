import XCTest
@testable import ClaudeUsageBarCore

final class AccountUsageProviderTests: XCTestCase {
    private static let usageURL = "https://api.anthropic.com/api/oauth/usage"

    private let account = Account(
        configDirectory: URL(filePath: "/tmp/.claude-test"),
        emailAddress: "a@example.com",
        organizationName: nil,
        accountUUID: "uuid"
    )

    private static func credentials(expiresAt: Date?) -> OAuthCredentials {
        OAuthCredentials(accessToken: "access-1", expiresAt: expiresAt, subscriptionType: "team")
    }

    private func provider(_ credentials: OAuthCredentials, _ transport: StubTransport) -> AccountUsageProvider {
        provider(loader: { _ in credentials }, transport)
    }

    private func provider(loader: @escaping CredentialLoader, _ transport: StubTransport) -> AccountUsageProvider {
        AccountUsageProvider(loadCredentials: loader, client: UsageClient(transport: transport))
    }

    func testValidTokenFetchesLiveUsage() async throws {
        let transport = StubTransport([.ok(#"{"limits":[]}"#)])
        let credentials = Self.credentials(expiresAt: Date(timeIntervalSinceNow: 3600))
        let usage = try await provider(credentials, transport).fetch(for: account)

        XCTAssertEqual(usage.subscriptionType, "team")
        XCTAssertEqual(usage.state, .live(rawUsage: Data(#"{"limits":[]}"#.utf8)))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [Self.usageURL])
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
    }

    func testUnknownExpiryIsTreatedAsValid() async throws {
        let transport = StubTransport([.ok("{}")])
        let usage = try await provider(Self.credentials(expiresAt: nil), transport).fetch(for: account)
        XCTAssertEqual(usage.state, .live(rawUsage: Data("{}".utf8)))
    }

    func testExpiredTokenReportsIdleAndSendsNothing() async throws {
        let transport = StubTransport([.ok("{}")])
        let expiredAt = Date(timeIntervalSinceNow: -60)
        let usage = try await provider(Self.credentials(expiresAt: expiredAt), transport).fetch(for: account)

        XCTAssertEqual(usage.subscriptionType, "team")
        XCTAssertEqual(usage.state, .idle(expiredAt: expiredAt))
        let sent = await transport.requests.count
        XCTAssertEqual(sent, 0, "an expired token must never trigger a request — refreshing would sign Claude Code out")
    }

    func testUnauthorizedIsNotRetried() async throws {
        let transport = StubTransport([StubTransport.Response(status: 401, body: ""), .ok("{}")])
        let credentials = Self.credentials(expiresAt: Date(timeIntervalSinceNow: 3600))
        await assertThrows(try await provider(credentials, transport).fetch(for: account)) { error in
            guard case UsageError.unauthorized = error else { return XCTFail("got \(error)") }
        }
        let sent = await transport.requests.count
        XCTAssertEqual(sent, 1)
    }

    func testCredentialLoadFailurePropagates() async throws {
        let transport = StubTransport([])
        let provider = provider(loader: { _ in throw KeychainError.notFound(services: ["x"]) }, transport)
        await assertThrows(try await provider.fetch(for: account)) { error in
            XCTAssertEqual(error as? KeychainError, .notFound(services: ["x"]))
        }
    }
}

/// XCTAssertThrowsError for async expressions.
func assertThrows<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ check: (any Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {
        check(error)
    }
}
