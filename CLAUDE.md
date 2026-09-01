# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Build & Run

SwiftPM package (no Xcode project — `.xcodeproj` is gitignored). Xcode opens `Package.swift` directly.

- **Build**: `swift build`
- **Test**: `swift test`
- **Probe live accounts**: `swift run usage-probe` — prints discovered accounts, resolved Keychain
  service names, and the raw `/api/oauth/usage` response. Never prints the access token.

Target: macOS 14+, Swift 6 strict concurrency.

## Architecture

**Data flow**: `~/.claude*` config dirs → `AccountScanner` → `KeychainCredentialStore` → `UsageClient` → menu bar UI

| Layer | Component | Role |
|-------|-----------|------|
| Discovery | `AccountScanner` | Scans `$HOME` for `.claude*` dirs holding a `.claude.json` with an `oauthAccount` |
| Credentials | `KeychainCredentialStore` | Derives the Keychain service name per config dir, reads the OAuth token |
| Network | `UsageClient` | `GET https://api.anthropic.com/api/oauth/usage` with a bearer token |

### Keychain service-name derivation

Claude Code decides the service name by whether `CLAUDE_CONFIG_DIR` was set **at login time**:

- unset → `Claude Code-credentials`
- set → `Claude Code-credentials-<first 8 hex of sha256(NFC(configDirPath))>`

The **presence of the variable** decides, not the path — `CLAUDE_CONFIG_DIR=$HOME/.claude` produces a
suffixed name for the default directory. We cannot see the logging-in process's environment, so
`serviceNames(for:)` returns candidates: the default directory tries the bare name first and falls
back to the suffixed one; every other directory uses the suffixed name only.

The Keychain account (`kSecAttrAccount`) is `$USER`.

### Usage response shape

`limits` is the canonical, self-describing list and what the UI should render:

```
limits: [{ group, kind, percent, resets_at, scope: { model: { display_name } }, severity, is_active }]
```

`kind` observed: `session`, `weekly_all`, `weekly_scoped`. Sibling top-level keys (`five_hour`,
`seven_day`, `seven_day_opus`, …) carry the same numbers in a flatter form; unreleased buckets appear
under codenames (`amber_ladder`, `tangelo`, …) and are almost always `null`. Prefer `limits`.

`spend` carries usage credits: `{ enabled, percent, used: { amount_minor, currency, exponent }, limit,
balance, auto_reload, can_purchase_credits, disabled_reason }`.

The plan label ("max", "team") comes from `subscriptionType` in the Keychain payload, not this response.

## Code Patterns

- Core types are `Sendable` value types; no shared mutable state outside the UI layer.
- Keychain and parsing failures throw typed errors (`KeychainError`, `UsageError`) — never fail open.
- Tests cover derivation, parsing, and rejection paths; they use temporary directories, never `$HOME`.
