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

    func testDefaultDirectoryHasBareAndSuffixedCandidates() {
        let names = KeychainCredentialStore.serviceNames(for: Account.defaultConfigDirectory)
        XCTAssertEqual(names.first, "Claude Code-credentials")
        XCTAssertEqual(names.count, 2, "default dir must also carry the suffixed name")
        XCTAssertTrue(names[1].hasPrefix("Claude Code-credentials-"))
    }

    func testCustomDirectoryUsesOnlySuffixedService() {
        let names = KeychainCredentialStore.serviceNames(for: URL(filePath: "/Users/mike/.claude-insight"))
        XCTAssertEqual(names, ["Claude Code-credentials-3d38302d"])
    }

    // MARK: Freshest lineage

    private static func credentials(_ token: String, expiresAt: Date?) -> OAuthCredentials {
        OAuthCredentials(accessToken: token, expiresAt: expiresAt, subscriptionType: nil)
    }

    func testFreshestPicksLatestExpiryRegardlessOfOrder() {
        let stale = Self.credentials("stale", expiresAt: Date(timeIntervalSince1970: 1_000))
        let fresh = Self.credentials("fresh", expiresAt: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(KeychainCredentialStore.freshest([stale, fresh])?.accessToken, "fresh")
        XCTAssertEqual(KeychainCredentialStore.freshest([fresh, stale])?.accessToken, "fresh")
    }

    func testFreshestKeepsEarlierCandidateOnTie() {
        let first = Self.credentials("first", expiresAt: Date(timeIntervalSince1970: 1_000))
        let second = Self.credentials("second", expiresAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(KeychainCredentialStore.freshest([first, second])?.accessToken, "first")
    }

    func testFreshestPrefersKnownExpiryOverUnknown() {
        let unknown = Self.credentials("unknown", expiresAt: nil)
        let known = Self.credentials("known", expiresAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(KeychainCredentialStore.freshest([unknown, known])?.accessToken, "known")
    }

    func testFreshestOfNothingIsNil() {
        XCTAssertNil(KeychainCredentialStore.freshest([]))
    }

    // MARK: Selection — every read costs the user a Keychain prompt

    private final class Reads {
        var services: [String] = []
    }

    private func select(_ entries: [String: OAuthCredentials?], order: [String], reads: Reads) throws -> OAuthCredentials {
        try KeychainCredentialStore.select(from: order) { service in
            reads.services.append(service)
            return entries[service] ?? nil
        }
    }

    func testSelectStopsAtFirstValidEntryWithoutReadingTheRest() throws {
        let reads = Reads()
        let valid = Self.credentials("valid", expiresAt: Date(timeIntervalSinceNow: 3600))
        let picked = try select(["bare": valid, "suffixed": Self.credentials("other", expiresAt: Date(timeIntervalSinceNow: 7200))], order: ["bare", "suffixed"], reads: reads)
        XCTAssertEqual(picked.accessToken, "valid")
        XCTAssertEqual(reads.services, ["bare"], "the second entry must not be read — it would prompt")
    }

    func testSelectSkipsExpiredEntryForALaterValidOne() throws {
        let reads = Reads()
        let stale = Self.credentials("stale", expiresAt: Date(timeIntervalSinceNow: -60))
        let valid = Self.credentials("valid", expiresAt: Date(timeIntervalSinceNow: 3600))
        let picked = try select(["bare": stale, "suffixed": valid], order: ["bare", "suffixed"], reads: reads)
        XCTAssertEqual(picked.accessToken, "valid")
        XCTAssertEqual(reads.services, ["bare", "suffixed"])
    }

    func testSelectReturnsFreshestWhenAllExpired() throws {
        let older = Self.credentials("older", expiresAt: Date(timeIntervalSinceNow: -7200))
        let newer = Self.credentials("newer", expiresAt: Date(timeIntervalSinceNow: -60))
        let picked = try select(["bare": older, "suffixed": newer], order: ["bare", "suffixed"], reads: Reads())
        XCTAssertEqual(picked.accessToken, "newer")
    }

    func testSelectSkipsMissingEntries() throws {
        let valid = Self.credentials("valid", expiresAt: Date(timeIntervalSinceNow: 3600))
        let picked = try select(["suffixed": valid], order: ["bare", "suffixed"], reads: Reads())
        XCTAssertEqual(picked.accessToken, "valid")
    }

    func testSelectThrowsNotFoundListingAllCandidates() {
        XCTAssertThrowsError(try select([:], order: ["bare", "suffixed"], reads: Reads())) { error in
            XCTAssertEqual(error as? KeychainError, .notFound(services: ["bare", "suffixed"]))
        }
    }

    func testSelectPropagatesReadFailure() {
        XCTAssertThrowsError(try KeychainCredentialStore.select(from: ["bare"]) { _ in throw KeychainError.unreadable(-25293) }) { error in
            XCTAssertEqual(error as? KeychainError, .unreadable(-25293))
        }
    }

    // MARK: Decoding

    func testDecodeExtractsTokenExpiriesAndPlan() throws {
        let payload = #"""
        {"claudeAiOauth":{"accessToken":"abc123","expiresAt":1788183139338,"refreshTokenExpiresAt":1789156989659,
         "refreshToken":"rt-1","scopes":["user:profile"],"subscriptionType":"max"}}
        """#
        let credentials = try KeychainCredentialStore.decode(Data(payload.utf8))
        XCTAssertEqual(credentials.accessToken, "abc123")
        XCTAssertEqual(credentials.subscriptionType, "max")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1788183139.338))
        XCTAssertEqual(credentials.refreshTokenExpiresAt, Date(timeIntervalSince1970: 1789156989.659))
    }

    func testDecodeTreatsZeroOrMissingExpiryAsUnknown() throws {
        let zero = try KeychainCredentialStore.decode(Data(#"{"claudeAiOauth":{"accessToken":"abc123","expiresAt":0,"refreshTokenExpiresAt":0}}"#.utf8))
        XCTAssertNil(zero.expiresAt)
        XCTAssertNil(zero.refreshTokenExpiresAt)

        let missing = try KeychainCredentialStore.decode(Data(#"{"claudeAiOauth":{"accessToken":"abc123"}}"#.utf8))
        XCTAssertNil(missing.expiresAt)
        XCTAssertNil(missing.refreshTokenExpiresAt)
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
        let past = Self.credentials("t", expiresAt: Date(timeIntervalSinceNow: -60))
        let future = Self.credentials("t", expiresAt: Date(timeIntervalSinceNow: 60))
        let unknown = Self.credentials("t", expiresAt: nil)
        XCTAssertTrue(past.isExpired)
        XCTAssertFalse(future.isExpired)
        XCTAssertFalse(unknown.isExpired)
    }
}
