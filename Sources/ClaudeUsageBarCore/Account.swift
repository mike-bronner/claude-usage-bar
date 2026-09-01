import Foundation

/// A Claude Code account, identified by the config directory that owns its login.
public struct Account: Identifiable, Hashable, Sendable {
    /// Absolute path to the config directory (e.g. `~/.claude`, `~/.claude-insight`).
    public let configDirectory: URL
    public let emailAddress: String
    public let organizationName: String?
    public let accountUUID: String

    public var id: String { configDirectory.path }

    /// True when this is the default config directory, whose Keychain entry is unsuffixed.
    public var isDefault: Bool { configDirectory.path == Self.defaultConfigDirectory.path }

    /// Label shown in the menu: the organization when it is a real one, else the email's local
    /// part. Personal accounts get an auto-generated "<email>'s Organization", which is no label.
    public var displayName: String {
        if let organizationName, !organizationName.contains(emailAddress) { return organizationName }
        return String(emailAddress.prefix(while: { $0 != "@" }))
    }

    public static var defaultConfigDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    }

    public init(configDirectory: URL, emailAddress: String, organizationName: String?, accountUUID: String) {
        self.configDirectory = configDirectory
        self.emailAddress = emailAddress
        self.organizationName = organizationName
        self.accountUUID = accountUUID
    }
}

/// Finds Claude Code accounts by scanning the home directory for config directories.
///
/// A directory qualifies only when it contains a `.claude.json` carrying an `oauthAccount`
/// object — which excludes non-account siblings such as `~/.claude-memory-cache`.
public struct AccountScanner: Sendable {
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan() throws -> [Account] {
        // Config directories are dot-prefixed, so hidden entries must be included.
        let contents = try FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        return contents
            .filter { $0.lastPathComponent.hasPrefix(".claude") }
            .compactMap(Self.account(inConfigDirectory:))
            .sorted(by: Self.defaultFirstThenName)
    }

    /// Default account leads; the rest sort by display name.
    static func defaultFirstThenName(_ lhs: Account, _ rhs: Account) -> Bool {
        lhs.isDefault == rhs.isDefault ? lhs.displayName < rhs.displayName : lhs.isDefault
    }

    /// Reads `<dir>/.claude.json` and returns an account when it holds a complete `oauthAccount`.
    static func account(inConfigDirectory directory: URL) -> Account? {
        let configFile = directory.appending(path: ".claude.json")
        guard let data = try? Data(contentsOf: configFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["oauthAccount"] as? [String: Any],
              let email = oauth["emailAddress"] as? String,
              let uuid = oauth["accountUuid"] as? String
        else { return nil }

        return Account(
            configDirectory: directory,
            emailAddress: email,
            organizationName: oauth["organizationName"] as? String,
            accountUUID: uuid
        )
    }
}
