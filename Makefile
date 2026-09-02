# Every `swift build` re-links with an ad-hoc signature. Signing with a real certificate keeps the
# code identity stable across rebuilds, which `SMAppService` (Launch at Login) needs. Override
# SIGN_IDENTITY with any identity from `security find-identity -v -p codesigning`.
SIGN_IDENTITY ?= 8185B645F6CE322D9D1E074100EE3A42965B2181

APP      = .build/ClaudeUsageBar.app
CONTENTS = $(APP)/Contents
BUILD    = $(shell git rev-list --count HEAD)

.PHONY: build test probe run bundle install

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

# Assembles ClaudeUsageBar.app from a release build: Info.plist (LSUIElement), an icon rendered
# from the same glyph as the menu bar item, and a signature with the stable identity.
bundle:
	swift build -c release
	rm -rf $(APP) .build/AppIcon.iconset
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/release/ClaudeUsageBar $(CONTENTS)/MacOS/
	cp Support/Info.plist $(CONTENTS)/Info.plist
	plutil -replace CFBundleVersion -string "$(BUILD)" $(CONTENTS)/Info.plist
	.build/release/render-icon .build/AppIcon.iconset
	iconutil -c icns .build/AppIcon.iconset -o $(CONTENTS)/Resources/AppIcon.icns
	codesign --force --sign $(SIGN_IDENTITY) $(APP)
	codesign --verify --strict $(APP) && echo "bundled $(APP) (build $(BUILD))"

# Replaces the copy in /Applications and launches it.
install: bundle
	-pkill -x ClaudeUsageBar
	rm -rf /Applications/ClaudeUsageBar.app
	cp -R $(APP) /Applications/
	open /Applications/ClaudeUsageBar.app
