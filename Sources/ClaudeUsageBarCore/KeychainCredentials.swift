import CryptoKit
import Foundation
import Security

/// The OAuth token set Claude Code stores in the login Keychain.
public struct OAuthCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?

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
/// environment of the process that logged in, so we derive candidates from the directory path
/// and try each in turn.
public struct KeychainCredentialStore: Sendable {
    static let serviceBase = "Claude Code-credentials"

    private let account: String

    public init(account: String = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()) {
        self.account = account
    }

    /// Service-name candidates for a config directory, most likely first.
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

    public func credentials(for configDirectory: URL) throws -> OAuthCredentials {
        let candidates = Self.serviceNames(for: configDirectory)
        for service in candidates {
            let (data, status) = read(service: service)
            if let data { return try Self.decode(data) }
            guard status == errSecItemNotFound else { throw KeychainError.unreadable(status) }
        }
        throw KeychainError.notFound(services: candidates)
    }

    private func read(service: String) -> (data: Data?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return (nil, status) }
        return (data, status)
    }

    static func decode(_ data: Data) throws -> OAuthCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { throw KeychainError.malformedPayload }

        // expiresAt is milliseconds since epoch; absent or zero means "no known expiry".
        let expiryMilliseconds = oauth["expiresAt"] as? Double ?? 0
        return OAuthCredentials(
            accessToken: token,
            expiresAt: expiryMilliseconds > 0 ? Date(timeIntervalSince1970: expiryMilliseconds / 1000) : nil,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }
}
