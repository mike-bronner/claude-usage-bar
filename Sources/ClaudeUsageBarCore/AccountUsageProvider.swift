import Foundation

/// One account's usage, or the fact that it is idle.
public struct AccountUsage: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// The stored access token is valid: Claude Code is in use and the numbers are current.
        case live(rawUsage: Data)
        /// Every stored token has expired. Claude Code refreshes silently on its next use, so the
        /// account is merely idle — and the numbers are whatever the UI last saw.
        case idle(expiredAt: Date)
    }

    public let subscriptionType: String?
    public let state: State
}

public typealias CredentialLoader = @Sendable (URL) throws -> OAuthCredentials

/// Fetches usage per account, strictly read-only over Claude Code's credentials.
///
/// An expired token is never refreshed here: the token endpoint rotates and revokes the refresh
/// token on every call, so refreshing out-of-process signs that account out of Claude Code
/// (verified live, 2026-09-01). The account is reported idle instead.
public struct AccountUsageProvider: Sendable {
    private let loadCredentials: CredentialLoader
    private let client: UsageClient

    public init(
        loadCredentials: @escaping CredentialLoader = { try KeychainCredentialStore().credentials(for: $0) },
        client: UsageClient = UsageClient()
    ) {
        self.loadCredentials = loadCredentials
        self.client = client
    }

    public func fetch(for account: Account) async throws -> AccountUsage {
        let stored = try loadCredentials(account.configDirectory)
        if let expiresAt = stored.expiresAt, stored.isExpired {
            return AccountUsage(subscriptionType: stored.subscriptionType, state: .idle(expiredAt: expiresAt))
        }
        let data = try await client.fetchRaw(accessToken: stored.accessToken)
        return AccountUsage(subscriptionType: stored.subscriptionType, state: .live(rawUsage: data))
    }
}
