# Claude Usage Bar

A macOS menu bar app showing Claude plan usage across every Claude Code account on the machine.

Accounts are discovered by scanning `$HOME` for `.claude*` config directories that hold a
`.claude.json` with an `oauthAccount`, so any number of accounts works with no configuration.

## Status

Complete for daily use: account discovery, per-directory Keychain credential lookup, usage fetch,
idle detection, the menu bar UI, and a signed `.app` (`make install`) with Launch at Login.

The app is strictly read-only over Claude Code's credentials — it never refreshes a token, because
doing so would sign that account out of Claude Code. An account whose token has expired is shown
as idle until Claude Code is used again.

## Development

```bash
swift build
swift test
make run     # run the menu bar app unbundled (codesigned, so the Keychain prompt sticks)
make probe   # inspect live accounts and the raw usage response
make bundle  # assemble and sign .build/ClaudeUsageBar.app
make install # bundle, copy to /Applications, launch
```

See [CLAUDE.md](CLAUDE.md) for architecture and the Keychain service-name derivation.
