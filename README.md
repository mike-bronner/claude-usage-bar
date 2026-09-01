# Claude Usage Bar

A macOS menu bar app showing Claude plan usage across every Claude Code account on the machine.

Accounts are discovered by scanning `$HOME` for `.claude*` config directories that hold a
`.claude.json` with an `oauthAccount`, so any number of accounts works with no configuration.

## Status

Core in place: account discovery, per-directory Keychain credential lookup, usage fetch.
Menu bar UI pending.

## Development

```bash
swift build
swift test
swift run usage-probe   # inspect live accounts and the raw usage response
```

See [CLAUDE.md](CLAUDE.md) for architecture and the Keychain service-name derivation.
