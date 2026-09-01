import ClaudeUsageBarCore
import Foundation

// Development probe: confirms account discovery, Keychain lookup, and the shape of the
// /api/oauth/usage response. Prints usage data and never prints any token.

let accounts = try AccountScanner().scan()
guard !accounts.isEmpty else {
    FileHandle.standardError.write(Data("no Claude accounts found\n".utf8))
    exit(1)
}

let store = KeychainCredentialStore()
let provider = AccountUsageProvider()
let iso = ISO8601DateFormatter()

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

    let expiry = credentials.expiresAt.map(iso.string(from:)) ?? "none"
    let loginExpiry = credentials.refreshTokenExpiresAt.map(iso.string(from:)) ?? "none"
    print("   keychain ✅ token \(credentials.accessToken.count) chars · plan \(credentials.subscriptionType ?? "?") · expires \(expiry) · login expires \(loginExpiry)")

    do {
        switch try await provider.fetch(for: account).state {
        case .idle(let expiredAt):
            print("   usage    ⏸️ idle since \(iso.string(from: expiredAt)) · please open Claude Code to refresh")
        case .live(let data):
            let object = try JSONSerialization.jsonObject(with: data)
            let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            print("   usage    ✅\n\(String(decoding: pretty, as: UTF8.self))")
        }
    } catch {
        print("   usage    ❌ \(error)")
    }
}
