import XCTest
@testable import ClaudeUsageBarCore

final class KeychainCredentialsTests: XCTestCase {
    func testPathHashMatchesClaudeCodeDerivation() {
        // Values derived from Claude Code's own sha256(NFC(path)).prefix(8) rule.
        XCTAssertEqual(KeychainCredentialStore.pathHash(URL(filePath: "/Users/mike/.claude")), "fb39db7b")
        XCTAssertEqual(KeychainCredentialStore.pathHash(URL(filePath: "/Users/mike/.claude-insight")), "3d38302d")
    }

    func testPathHashIsSensitiveToPath() {
        XCTAssertNotEqual(
            KeychainCredentialStore.pathHash(URL(filePath: "/Users/mike/.claude")),
            KeychainCredentialStore.pathHash(URL(filePath: "/Users/mike/.claude2"))
        )
    }

    func testDefaultDirectoryTriesBareServiceFirst() {
        let names = KeychainCredentialStore.serviceNames(for: Account.defaultConfigDirectory)
        XCTAssertEqual(names.first, "Claude Code-credentials")
        XCTAssertEqual(names.count, 2, "default dir must also fall back to the suffixed name")
        XCTAssertTrue(names[1].hasPrefix("Claude Code-credentials-"))
    }

    func testCustomDirectoryUsesOnlySuffixedService() {
        let names = KeychainCredentialStore.serviceNames(for: URL(filePath: "/Users/mike/.claude-insight"))
        XCTAssertEqual(names, ["Claude Code-credentials-3d38302d"])
    }

    func testDecodeExtractsTokenExpiryAndPlan() throws {
        let payload = #"{"claudeAiOauth":{"accessToken":"abc123","expiresAt":1788183139338,"subscriptionType":"max"}}"#
        let credentials = try KeychainCredentialStore.decode(Data(payload.utf8))
        XCTAssertEqual(credentials.accessToken, "abc123")
        XCTAssertEqual(credentials.subscriptionType, "max")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1788183139.338))
    }

    func testDecodeTreatsZeroExpiryAsUnknown() throws {
        let payload = #"{"claudeAiOauth":{"accessToken":"abc123","expiresAt":0}}"#
        XCTAssertNil(try KeychainCredentialStore.decode(Data(payload.utf8)).expiresAt)
    }

    func testDecodeRejectsMissingOAuthObject() {
        let payload = #"{"somethingElse":{"accessToken":"abc123"}}"#
        XCTAssertThrowsError(try KeychainCredentialStore.decode(Data(payload.utf8)))
    }

    func testDecodeRejectsEmptyToken() {
        let payload = #"{"claudeAiOauth":{"accessToken":""}}"#
        XCTAssertThrowsError(try KeychainCredentialStore.decode(Data(payload.utf8)))
    }

    func testIsExpiredReflectsExpiry() {
        let past = OAuthCredentials(accessToken: "t", expiresAt: Date(timeIntervalSinceNow: -60), subscriptionType: nil)
        let future = OAuthCredentials(accessToken: "t", expiresAt: Date(timeIntervalSinceNow: 60), subscriptionType: nil)
        let unknown = OAuthCredentials(accessToken: "t", expiresAt: nil, subscriptionType: nil)
        XCTAssertTrue(past.isExpired)
        XCTAssertFalse(future.isExpired)
        XCTAssertFalse(unknown.isExpired)
    }
}
