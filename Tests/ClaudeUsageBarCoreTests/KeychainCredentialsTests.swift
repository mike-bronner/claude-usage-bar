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
        let credentials = try XCTUnwrap(KeychainCredentialStore.decode(Data(payload.utf8)))
        XCTAssertEqual(credentials.accessToken, "abc123")
        XCTAssertEqual(credentials.subscriptionType, "max")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1788183139.338))
        XCTAssertEqual(credentials.refreshTokenExpiresAt, Date(timeIntervalSince1970: 1789156989.659))
    }

    func testDecodeTreatsZeroOrMissingExpiryAsUnknown() throws {
        let zero = try XCTUnwrap(KeychainCredentialStore.decode(Data(#"{"claudeAiOauth":{"accessToken":"abc123","expiresAt":0,"refreshTokenExpiresAt":0}}"#.utf8)))
        XCTAssertNil(zero.expiresAt)
        XCTAssertNil(zero.refreshTokenExpiresAt)

        let missing = try XCTUnwrap(KeychainCredentialStore.decode(Data(#"{"claudeAiOauth":{"accessToken":"abc123"}}"#.utf8)))
        XCTAssertNil(missing.expiresAt)
        XCTAssertNil(missing.refreshTokenExpiresAt)
    }

    // A format change must stay loud: these three are the app's only warning that Claude Code
    // moved the payload, so each one keeps throwing.

    func testDecodeRejectsMissingOAuthObject() {
        let payload = #"{"somethingElse":{"accessToken":"abc123"}}"#
        XCTAssertThrowsError(try KeychainCredentialStore.decode(Data(payload.utf8))) { error in
            XCTAssertEqual(error as? KeychainError, .malformedPayload)
        }
    }

    func testDecodeRejectsUnparseablePayload() {
        XCTAssertThrowsError(try KeychainCredentialStore.decode(Data("not json at all".utf8))) { error in
            XCTAssertEqual(error as? KeychainError, .malformedPayload)
        }
    }

    func testDecodeRejectsTokenOfTheWrongType() {
        let payload = #"{"claudeAiOauth":{"accessToken":42}}"#
        XCTAssertThrowsError(try KeychainCredentialStore.decode(Data(payload.utf8))) { error in
            XCTAssertEqual(error as? KeychainError, .malformedPayload)
        }
    }

    /// A blank or absent token is a signed-out lineage, not corruption: it carries no credentials,
    /// exactly like a Keychain item that is not there, so the caller skips to the next candidate.
    func testDecodeTreatsBlankOrAbsentTokenAsNoCredentials() throws {
        XCTAssertNil(try KeychainCredentialStore.decode(Data(#"{"claudeAiOauth":{"accessToken":"","expiresAt":0}}"#.utf8)))
        XCTAssertNil(try KeychainCredentialStore.decode(Data(#"{"claudeAiOauth":{"expiresAt":0}}"#.utf8)))
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

// MARK: - Reading through /usr/bin/security

final class KeychainToolReadTests: XCTestCase {
    private static let payload = Data(#"{"claudeAiOauth":{"accessToken":"abc123","expiresAt":1788183139338,"subscriptionType":"max"}}"#.utf8)

    private final class Calls: @unchecked Sendable {
        var arguments: [[String]] = []
    }

    /// A store whose tool is scripted: `respond` maps the service name to (stdout, exit code).
    private func store(_ calls: Calls, respond: @escaping @Sendable (String) -> (Data, Int32)) -> KeychainCredentialStore {
        KeychainCredentialStore(account: "mike") { arguments in
            calls.arguments.append(arguments)
            let service = arguments[arguments.firstIndex(of: "-s")! + 1]
            return respond(service)
        }
    }

    func testReadPassesAccountAndServiceAndNeverTheSecret() throws {
        let calls = Calls()
        let store = store(calls) { _ in (Self.payload + Data("\n".utf8), 0) }
        _ = try store.read(service: "Claude Code-credentials-3d38302d")
        XCTAssertEqual(calls.arguments, [["find-generic-password", "-a", "mike", "-s", "Claude Code-credentials-3d38302d", "-w"]])
    }

    func testTextOutputIsReturnedWithoutTrailingNewline() throws {
        let store = store(Calls()) { _ in (Self.payload + Data("\n".utf8), 0) }
        XCTAssertEqual(try store.read(service: "any"), Self.payload)
    }

    func testHexOutputIsDecoded() throws {
        let hex = Self.payload.map { String(format: "%02x", $0) }.joined() + "\n"
        let store = store(Calls()) { _ in (Data(hex.utf8), 0) }
        XCTAssertEqual(try store.read(service: "any"), Self.payload)
    }

    func testExit44IsAMissingItem() throws {
        let store = store(Calls()) { _ in (Data(), 44) }
        XCTAssertNil(try store.read(service: "any"))
    }

    func testExit36IsUnreadableNotAFallback() {
        let calls = Calls()
        let store = store(calls) { _ in (Data(), 36) }
        XCTAssertThrowsError(try store.read(service: "any")) { error in
            XCTAssertEqual(error as? KeychainError, .unreadable(36))
        }
        XCTAssertEqual(calls.arguments.count, 1, "a locked Keychain must not fall through to a prompting read")
    }

    func testMissingBareEntryFallsThroughToSuffixedCandidate() throws {
        let calls = Calls()
        let store = store(calls) { service in service.hasSuffix("-fb39db7b") ? (Self.payload, 0) : (Data(), 44) }
        let credentials = try store.credentials(for: URL(filePath: "/Users/mike/.claude"))
        XCTAssertEqual(credentials.accessToken, "abc123")
        XCTAssertEqual(calls.arguments.count, 2)
    }

    // MARK: A signed-out lineage in front of the live one

    /// The bare entry as it read live on 2026-09-17: well-formed, every key present, token blank.
    private static let signedOutPayload = Data(
        #"{"claudeAiOauth":{"accessToken":"","expiresAt":0,"refreshTokenExpiresAt":1789156989659,"subscriptionType":"max"}}"#.utf8
    )

    private static func livePayload(token: String) -> Data {
        let expiresAt = (Date(timeIntervalSinceNow: 3600).timeIntervalSince1970 * 1000).rounded()
        return Data(#"{"claudeAiOauth":{"accessToken":"\#(token)","expiresAt":\#(expiresAt),"subscriptionType":"max"}}"#.utf8)
    }

    private static var defaultDirectory: URL { Account.defaultConfigDirectory }

    func testSignedOutFirstCandidateFallsThroughToTheLiveOne() throws {
        let calls = Calls()
        let store = store(calls) { service in
            service == KeychainCredentialStore.serviceBase ? (Self.signedOutPayload, 0) : (Self.livePayload(token: "live"), 0)
        }
        let credentials = try store.credentials(for: Self.defaultDirectory)
        XCTAssertEqual(credentials.accessToken, "live")
        XCTAssertEqual(calls.arguments.count, 2, "a blank token must not end the lookup")
    }

    func testEverySignedOutCandidateStillReportsNotFound() {
        let store = store(Calls()) { _ in (Self.signedOutPayload, 0) }
        XCTAssertThrowsError(try store.credentials(for: Self.defaultDirectory)) { error in
            XCTAssertEqual(
                error as? KeychainError,
                .notFound(services: KeychainCredentialStore.serviceNames(for: Self.defaultDirectory))
            )
        }
    }

    func testCorruptFirstCandidateStillThrowsWithALiveSecondBehindIt() {
        let calls = Calls()
        let store = store(calls) { service in
            service == KeychainCredentialStore.serviceBase ? (Data("not json at all".utf8), 0) : (Self.livePayload(token: "live"), 0)
        }
        XCTAssertThrowsError(try store.credentials(for: Self.defaultDirectory)) { error in
            XCTAssertEqual(error as? KeychainError, .malformedPayload)
        }
        XCTAssertEqual(calls.arguments.count, 1, "corruption stops the lookup — a working sibling must not hide it")
    }

    func testSecretDecodingHelpers() {
        XCTAssertEqual(KeychainCredentialStore.secret(from: Data("{\"a\":1}\r\n".utf8)), Data("{\"a\":1}".utf8))
        XCTAssertEqual(KeychainCredentialStore.hexDecoded(Data("7b7d".utf8)), Data("{}".utf8))
        XCTAssertNil(KeychainCredentialStore.hexDecoded(Data("7b7".utf8)), "odd length is not hex")
        XCTAssertNil(KeychainCredentialStore.hexDecoded(Data("zz".utf8)), "non-hex bytes are not hex")
        XCTAssertNil(KeychainCredentialStore.hexDecoded(Data()))
    }
}
