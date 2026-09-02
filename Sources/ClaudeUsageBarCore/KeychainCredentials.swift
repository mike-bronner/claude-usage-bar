import CryptoKit
import Foundation
import Security

/// The OAuth token set Claude Code stores in the login Keychain.
///
/// Only what the app reads is decoded. The refresh token is deliberately left out: refreshing
/// out-of-process revokes Claude Code's copy and signs the account out.
public struct OAuthCredentials: Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Date?
    /// When the refresh token — the login itself — expires and Claude Code will ask for `/login`.
    public let refreshTokenExpiresAt: Date?
    public let subscriptionType: String?
    /// Tier code such as `default_claude_max_20x`; the "(20x)" in the plan label comes from here.
    public let rateLimitTier: String?

    public init(
        accessToken: String, expiresAt: Date?, refreshTokenExpiresAt: Date? = nil,
        subscriptionType: String?, rateLimitTier: String? = nil
    ) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    public var isExpired: Bool { expiresAt.map { $0 <= Date() } ?? false }
}

public enum KeychainError: Error, Equatable {
    case notFound(services: [String])
    case unreadable(OSStatus)
    case malformedPayload
}

/// Reads Claude Code's OAuth credentials out of the login Keychain.
///
/// Claude Code derives the Keychain service name from whether `CLAUDE_CONFIG_DIR` was set
/// when the login happened: unset yields the bare `Claude Code-credentials`, set yields
/// `Claude Code-credentials-<first 8 hex of sha256(NFC(configDirPath))>`. We cannot read the
/// environment of the process that logged in, so we derive candidates from the directory path.
/// Several can exist at once, each an independent token lineage.
///
/// The read goes through `/usr/bin/security`, not `SecItemCopyMatching`. Claude Code writes the
/// item with `security add-generic-password -U`, and that update resets the item's partition list
/// to `apple-tool:`, dropping the `teamid:` grant an "Always Allow" had added — so a direct read
/// re-prompted (password included) after every token rotation. The `security` tool sits in
/// `apple-tool:` itself, so a read through it never prompts; it is how Claude Code reads its own
/// token. Verified 2026-09-02.
public struct KeychainCredentialStore: Sendable {
    static let serviceBase = "Claude Code-credentials"

    /// Runs `/usr/bin/security` with `arguments`, returning its standard output and exit status.
    /// Injected so tests never touch the Keychain.
    public typealias ToolRunner = @Sendable (_ arguments: [String]) throws -> (output: Data, exitCode: Int32)

    private let account: String
    private let runTool: ToolRunner

    public init(
        account: String = ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
        runTool: @escaping ToolRunner = Self.runSecurityTool
    ) {
        self.account = account
        self.runTool = runTool
    }

    /// Spawns `/usr/bin/security`. The secret arrives on stdout, never in `argv`, so `ps` shows
    /// only the account and service names. Blocks for the tool's run (≈0.4 s); callers are off
    /// the main thread.
    public static let runSecurityTool: ToolRunner = { arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (output, process.terminationStatus)
    }

    /// Service-name candidates for a config directory. Only the default directory can carry the
    /// bare name; every directory can carry the suffixed one.
    public static func serviceNames(for configDirectory: URL) -> [String] {
        let suffixed = "\(serviceBase)-\(pathHash(configDirectory))"
        return configDirectory.path == Account.defaultConfigDirectory.path
            ? [serviceBase, suffixed]
            : [suffixed]
    }

    /// First 8 hex characters of sha256 over the NFC-normalized directory path.
    static func pathHash(_ configDirectory: URL) -> String {
        let normalized = configDirectory.path.precomposedStringWithCanonicalMapping
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    /// Reads candidates in order and stops at the first valid token, so nothing is read that
    /// isn't needed; among expired entries the freshest wins. A missing candidate is fine, an
    /// unreadable or malformed one is not.
    public func credentials(for configDirectory: URL) throws -> OAuthCredentials {
        try Self.select(from: Self.serviceNames(for: configDirectory)) { service in
            try read(service: service).map(Self.decode)
        }
    }

    /// The tool exits with the `OSStatus` it hit: 44 is `errSecItemNotFound`, 36 is
    /// `errSecInteractionNotAllowed` (login Keychain locked, and no terminal to unlock it in),
    /// which is transient — the UI keeps its last snapshot. Any other failure, including a tool
    /// that will not launch, falls back to the direct read, so a future Claude Code that stores
    /// the item some other way degrades to a prompt rather than a blank menu.
    func read(service: String) throws -> Data? {
        let arguments = ["find-generic-password", "-a", account, "-s", service, "-w"]
        guard let (output, exitCode) = try? runTool(arguments) else { return try readDirectly(service: service) }
        switch exitCode {
        case 0: return Self.secret(from: output)
        case Self.toolItemNotFound: return nil
        case Self.toolInteractionNotAllowed: throw KeychainError.unreadable(exitCode)
        default: return try readDirectly(service: service)
        }
    }

    static let toolItemNotFound: Int32 = 44
    static let toolInteractionNotAllowed: Int32 = 36

    /// `-w` prints the secret followed by a newline — as text when it is printable, as hex
    /// otherwise. Claude Code's payload is JSON, so text is the norm; hex is decoded in case.
    static func secret(from output: Data) -> Data {
        var bytes = output
        while let last = bytes.last, last == UInt8(ascii: "\n") || last == UInt8(ascii: "\r") { bytes.removeLast() }
        return hexDecoded(bytes) ?? bytes
    }

    /// Nil unless every byte is a hex digit; JSON starts with `{`, so it can never be mistaken.
    static func hexDecoded(_ bytes: Data) -> Data? {
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { return nil }
        var decoded = Data(capacity: bytes.count / 2)
        var iterator = bytes.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            guard let high = nibble(high), let low = nibble(low) else { return nil }
            decoded.append(high << 4 | low)
        }
        return decoded
    }

    private static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// The selection rule, separated from the Keychain so it can be tested: `read` returns nil
    /// for a missing entry.
    static func select(from services: [String], read: (String) throws -> OAuthCredentials?) throws -> OAuthCredentials {
        var expired: [OAuthCredentials] = []
        for service in services {
            guard let credentials = try read(service) else { continue }
            if !credentials.isExpired { return credentials }
            expired.append(credentials)
        }
        guard let freshest = Self.freshest(expired) else { throw KeychainError.notFound(services: services) }
        return freshest
    }

    /// Among expired lineages, the one Claude Code used last has the latest expiry. Ties keep the
    /// earlier candidate; an unknown expiry loses to any known one.
    static func freshest(_ candidates: [OAuthCredentials]) -> OAuthCredentials? {
        candidates.max { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }
    }

    /// The fallback: `SecItemCopyMatching` prompts once per token rotation (see the type comment).
    private func readDirectly(service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError.unreadable(status) }
        return data
    }

    static func decode(_ data: Data) throws -> OAuthCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { throw KeychainError.malformedPayload }

        return OAuthCredentials(
            accessToken: token,
            expiresAt: Self.date(fromMilliseconds: oauth["expiresAt"]),
            refreshTokenExpiresAt: Self.date(fromMilliseconds: oauth["refreshTokenExpiresAt"]),
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }

    /// Expiry fields are milliseconds since epoch; absent or zero means "no known expiry".
    private static func date(fromMilliseconds value: Any?) -> Date? {
        guard let milliseconds = value as? Double, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
