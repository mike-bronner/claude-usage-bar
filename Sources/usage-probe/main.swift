import ClaudeUsageBarCore
import Foundation

// Development probe: confirms account discovery, Keychain lookup, and the shape of the
// /api/oauth/usage response. Prints usage data and never prints the access token.

let accounts = try AccountScanner().scan()
guard !accounts.isEmpty else {
    FileHandle.standardError.write(Data("no Claude accounts found\n".utf8))
    exit(1)
}

let store = KeychainCredentialStore()

for account in accounts {
    print("── \(account.displayName) <\(account.emailAddress)>")
    print("   dir      \(account.configDirectory.path)")
    print("   services \(KeychainCredentialStore.serviceNames(for: account.configDirectory).joined(separator: ", "))")

    let credentials: OAuthCredentials
    do {
        credentials = try store.credentials(for: account.configDirectory)
    } catch {
        print("   keychain ❌ \(error)")
        continue
    }

    let expiry = credentials.expiresAt.map(ISO8601DateFormatter().string(from:)) ?? "none"
    print("   keychain ✅ token \(credentials.accessToken.count) chars · plan \(credentials.subscriptionType ?? "?") · expires \(expiry)")

    do {
        let data = try await UsageClient().fetchRaw(accessToken: credentials.accessToken)
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        print("   usage    ✅\n\(String(decoding: pretty, as: UTF8.self))")
    } catch {
        print("   usage    ❌ \(error)")
    }
}
