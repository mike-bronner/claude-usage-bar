# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Build & Run

SwiftPM package (no Xcode project — `.xcodeproj` is gitignored). Xcode opens `Package.swift` directly.

- **Build**: `swift build`
- **Test**: `swift test` — no Keychain or network access; everything is stubbed via `Transport`.
- **Run the app (dev)**: `make run` — builds, codesigns `ClaudeUsageBar` with a stable identity, and
  runs it unbundled. It hides its Dock icon itself until `make bundle` supplies `LSUIElement`.
- **Probe live accounts**: `make probe` — same for `usage-probe`, which prints discovered accounts,
  resolved Keychain service names, and the raw `/api/oauth/usage` response. Never prints any token.
  (`swift run …` works too, but its ad-hoc signature changes every build, so the Keychain
  re-prompts each time.)

Target: macOS 14+, Swift 6 strict concurrency.

## Architecture

**Data flow**: `~/.claude*` config dirs → `AccountScanner` → `KeychainCredentialStore` → `AccountUsageProvider` → `UsageClient` → `UsageSnapshot` → `UsageModel` → `MenuBarExtra`

| Layer | Component | Role |
|-------|-----------|------|
| Discovery | `AccountScanner` | Scans `$HOME` for `.claude*` dirs holding a `.claude.json` with an `oauthAccount` |
| Credentials | `KeychainCredentialStore` | Derives the Keychain service names per config dir, reads the freshest OAuth token |
| Orchestration | `AccountUsageProvider` | Per account: fetch when the token is valid, report `.idle` when it is not |
| Network | `UsageClient` | `GET https://api.anthropic.com/api/oauth/usage` with a bearer token, over an injectable `Transport` |
| Decoding | `UsageSnapshot` | `limits` + `spend` → typed limits and credits; `ResetFormatter`, `PlanLabel` format them |
| Status | `StatusLevel` | Session percent + server `severity` + idle → one of idle/unknown/low/medium/high/critical |
| UI | `UsageModel`, `StatusItemController`, `UsageMenuContent`, `RobotIcon` | `@Observable` model polled every 15 min (the endpoint 429s under ~180 req/h and stays tripped for a long window); `NSStatusItem` + `NSMenu`; selected account persisted in `UserDefaults` |

The `ClaudeUsageBar` target holds the only mutable state (`UsageModel`, `@MainActor`). It keeps the
last snapshot through idle and failure so the menu dims numbers instead of blanking them. The menu
bar item is a robot glyph drawn in code, colored by the selected account's `StatusLevel` (grey when
idle or unknown, green → yellow → orange → red); no text.

The dropdown is a real `NSMenu`, not a `MenuBarExtra(.window)` panel — the HIG asks a menu bar
extra to show a menu, and only a menu gets the system's attached chrome. Standard items carry the
commands (Refresh ⌘R, Quit ⌘Q); one custom item hosts `UsageMenuContent` — account picker and usage
block — in an `NSHostingView`, the way Battery and Wi-Fi show status a plain item cannot. The picker
is in the custom view because a native item dismisses the menu when picked.

### Read-only over Claude Code's credentials — never refresh

**This app never calls the token endpoint.** Verified live on 2026-09-01: refreshing rotates the
refresh token *and revokes the old one* (a second refresh with the stored token returns HTTP 400).
Any out-of-process refresh therefore signs that account out of Claude Code on its next use.

An expired access token in the Keychain is not a logout, it is idleness: Claude Code refreshes
silently on next use and writes the result back. So `AccountUsageProvider` returns
`.idle(expiredAt:)` and the UI dims the last-known numbers with "please open Claude Code to
refresh". The real login is the refresh token (`refreshTokenExpiresAt`, weeks out); Claude Code
itself warns the user three days before it lapses.

### Keychain service-name derivation

Claude Code decides the service name by whether `CLAUDE_CONFIG_DIR` was set **at login time**:

- unset → `Claude Code-credentials`
- set → `Claude Code-credentials-<first 8 hex of sha256(NFC(configDirPath))>`

The **presence of the variable** decides, not the path — `CLAUDE_CONFIG_DIR=$HOME/.claude` produces a
suffixed name for the default directory. We cannot see the logging-in process's environment, so
`serviceNames(for:)` returns candidates: both names for the default directory, the suffixed name
only for every other.

**Both can exist at once**, each an independent token lineage (one login with the variable unset,
later sessions with it set). `credentials(for:)` reads every existing candidate and returns the
one with the latest `expiresAt` — the lineage Claude Code is actively using. Taking the first
match reads a stale lineage and reports a live account as idle.

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

The plan label comes from the Keychain payload, not this response: `subscriptionType` ("max",
"team") plus the multiplier parsed from `rateLimitTier` (`default_claude_max_20x` → "Max (20x)").
`spend` carries no reset date; the panel shows only what is present.

## Code Patterns

- Core types are `Sendable` value types; no shared mutable state outside the UI layer.
- Keychain and parsing failures throw typed errors (`KeychainError`, `UsageError`) — never fail open.
  A 401 on a token that looked valid is thrown, not retried.
- Tests cover derivation, parsing, and rejection paths; they use temporary directories, never `$HOME`,
  and script HTTP through `StubTransport` rather than touching the network or the Keychain.
