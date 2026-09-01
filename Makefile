# Keychain "Always Allow" grants bind to a binary's code identity, and every `swift build` re-links
# with an ad-hoc signature. Signing with a real certificate keeps the identity stable across
# rebuilds, so the grant survives. Override SIGN_IDENTITY with any identity from
# `security find-identity -v -p codesigning`.
SIGN_IDENTITY ?= 8185B645F6CE322D9D1E074100EE3A42965B2181

.PHONY: build test probe run

build:
	swift build

test:
	swift test

probe: build
	codesign --force --sign $(SIGN_IDENTITY) .build/debug/usage-probe
	.build/debug/usage-probe

# Runs the menu bar app unbundled, for development; `make bundle` produces the real .app.
run: build
	codesign --force --sign $(SIGN_IDENTITY) .build/debug/ClaudeUsageBar
	.build/debug/ClaudeUsageBar
