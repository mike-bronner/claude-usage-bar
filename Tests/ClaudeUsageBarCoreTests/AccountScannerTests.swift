import XCTest
@testable import ClaudeUsageBarCore

final class AccountScannerTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: home)
    }

    private func makeDirectory(_ name: String, config: String?) throws -> URL {
        let directory = home.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let config {
            try Data(config.utf8).write(to: directory.appending(path: ".claude.json"))
        }
        return directory
    }

    private static let validConfig = #"""
    {"oauthAccount":{"emailAddress":"a@example.com","accountUuid":"uuid-1","organizationName":"Acme"}}
    """#

    func testParsesAccountFromConfig() throws {
        let directory = try makeDirectory(".claude", config: Self.validConfig)
        let account = try XCTUnwrap(AccountScanner.account(inConfigDirectory: directory))
        XCTAssertEqual(account.emailAddress, "a@example.com")
        XCTAssertEqual(account.organizationName, "Acme")
        XCTAssertEqual(account.accountUUID, "uuid-1")
    }

    func testSkipsDirectoryWithoutConfigFile() throws {
        let directory = try makeDirectory(".claude-memory-cache", config: nil)
        XCTAssertNil(AccountScanner.account(inConfigDirectory: directory))
    }

    func testSkipsConfigWithoutOAuthAccount() throws {
        let directory = try makeDirectory(".claude-workbench", config: #"{"numStartups":4}"#)
        XCTAssertNil(AccountScanner.account(inConfigDirectory: directory))
    }

    func testSkipsConfigMissingAccountUUID() throws {
        let directory = try makeDirectory(".claude-partial", config: #"{"oauthAccount":{"emailAddress":"a@example.com"}}"#)
        XCTAssertNil(AccountScanner.account(inConfigDirectory: directory))
    }

    func testScanFindsOnlyAccountDirectories() throws {
        _ = try makeDirectory(".claude-one", config: Self.validConfig)
        _ = try makeDirectory(".claude-memory-cache", config: nil)
        _ = try makeDirectory(".config", config: Self.validConfig)

        let found = try AccountScanner(home: home).scan()
        XCTAssertEqual(found.map(\.configDirectory.lastPathComponent), [".claude-one"])
    }

    func testDisplayNameFallsBackToEmailLocalPart() {
        let account = Account(
            configDirectory: URL(filePath: "/tmp/.claude-x"),
            emailAddress: "someone@example.com",
            organizationName: nil,
            accountUUID: "uuid"
        )
        XCTAssertEqual(account.displayName, "someone")
    }

    func testDefaultAccountSortsFirst() {
        let other = Account(configDirectory: URL(filePath: "/tmp/.claude-a"), emailAddress: "a@x.com", organizationName: "AAA", accountUUID: "1")
        let standard = Account(configDirectory: Account.defaultConfigDirectory, emailAddress: "z@x.com", organizationName: "ZZZ", accountUUID: "2")
        XCTAssertTrue(AccountScanner.defaultFirstThenName(standard, other))
        XCTAssertFalse(AccountScanner.defaultFirstThenName(other, standard))
    }
}
