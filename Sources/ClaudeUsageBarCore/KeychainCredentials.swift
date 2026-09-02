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
public struct KeychainCredentialStore: Sendable {
    static let serviceBase = "Claude Code-credentials"

    private let account: String

    public init(account: String = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()) {
        self.account = account
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

    /// Reads candidates in order and stops at the first valid token. Every read of an item this
    /// app did not create costs the user a Keychain prompt, so no entry is read unless the ones
    /// before it are expired; among expired entries the freshest wins. A missing candidate is
    /// fine, an unreadable or malformed one is not.
    public func credentials(for configDirectory: URL) throws -> OAuthCredentials {
        try Self.select(from: Self.serviceNames(for: configDirectory)) { service in
            let (data, status) = read(service: service)
            guard let data else {
                if status == errSecItemNotFound { return nil }
                throw KeychainError.unreadable(status)
            }
            return try Self.decode(data)
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
