SHELL := /bin/bash

PROJECT := orchardgrid-app.xcodeproj
SCHEME  := orchardgrid-app
CLI_DIR := orchardgrid-cli

# `-allowProvisioningUpdates` lets Xcode auto-create / refresh App Group +
# other capability registrations in the Apple Developer portal. Without it,
# adding entitlements (e.g. App Groups for og state-sharing) would require
# manual portal config.
XCB     := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -quiet \
           -allowProvisioningUpdates
MAC_DST := generic/platform=macOS
IOS_DST := platform=iOS Simulator,name=iPhone 17

.PHONY: help build build-macos build-ios debug \
        test test-xcode test-xcode-macos test-xcode-ios test-cli \
        format clean open release-notes bundle bundle-cli

help: ## Show this help
	@awk 'BEGIN{FS=":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*##/ {printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: build-macos build-ios ## Release build for macOS and iOS

build-macos: ## Release build for macOS
	$(XCB) -configuration Release -destination '$(MAC_DST)' build

build-ios: ## Release build for iOS (iPhone 17 simulator, unsigned)
	$(XCB) -configuration Release -destination '$(IOS_DST)' \
		CODE_SIGNING_ALLOWED=NO build

debug: ## Debug build for macOS
	$(XCB) -configuration Debug -destination '$(MAC_DST)' build

# ── Bundle the og CLI inside the .app ───────────────────────────────────
# Phase 6: a single `brew install --cask orchardgrid` should give the user
# both the GUI and the `og` command. We achieve that by compiling og from
# its sibling SPM package, dropping it inside OrchardGrid.app/Contents/
# Resources/og, and ad-hoc signing it with the App Group entitlement so
# it can read state shared with the GUI app.
#
# The cask file in homebrew-orchardgrid then has one extra line:
#   binary "#{appdir}/OrchardGrid.app/Contents/Resources/og"
# which symlinks /opt/homebrew/bin/og → bundled binary at install time.

bundle: build-macos bundle-cli ## Build the app AND bundle og inside it (for local testing)

bundle-cli: ## Compile og + copy into the most recent OrchardGrid.app, ad-hoc signed
	@echo "→ building og release binary…"
	@cd $(CLI_DIR) && swift build -c release
	@APP=$$(find ~/Library/Developer/Xcode/DerivedData -name OrchardGrid.app -type d | head -1); \
	if [ -z "$$APP" ]; then \
		echo "error: OrchardGrid.app not found in DerivedData — run 'make build-macos' first"; \
		exit 1; \
	fi; \
	echo "→ copying og into $$APP/Contents/Resources/"; \
	cp $(CLI_DIR)/.build/release/og "$$APP/Contents/Resources/og"; \
	codesign --force --sign - \
		--entitlements orchardgrid-app/og.entitlements \
		--options runtime \
		"$$APP/Contents/Resources/og"; \
	echo "✓ og bundled (ad-hoc signed). Path: $$APP/Contents/Resources/og"

# ── Tests ────────────────────────────────────────────────────────────────
# Single entry point: `make test` runs EVERYTHING in this repo — the
# Xcode app test target on both macOS and iOS, plus the og CLI's Swift
# Testing unit suite and pytest integration suite. Sub-targets are
# composable so CI can parallelise them.

test: test-xcode test-cli ## Run every test in the repo (Xcode app + og CLI)

test-xcode: test-xcode-macos test-xcode-ios ## Xcode app test target on macOS + iOS

test-xcode-macos: ## Xcode app test target on macOS
	$(XCB) -configuration Debug -destination 'platform=macOS' test

test-xcode-ios: ## Xcode app test target on iPhone 17 simulator
	$(XCB) -configuration Debug -destination '$(IOS_DST)' test

test-cli: ## og CLI Swift unit + pytest integration suites
	$(MAKE) -C $(CLI_DIR) test

format: ## Format all Swift sources (swift-format)
	@command -v swift-format >/dev/null || { echo "swift-format not found — brew install swift-format"; exit 1; }
	swift-format format --configuration .swift-format --in-place --recursive .

clean: ## Remove build artifacts
	$(XCB) clean
	rm -rf build

open: ## Open project in Xcode
	open $(PROJECT)

release-notes: ## Print commits since last tag (for debugging release.yml)
	@LATEST=$$(git tag -l 'v*' --sort=-v:refname | head -1); \
	if [ -z "$$LATEST" ]; then git log --oneline; else git log "$$LATEST..HEAD" --oneline; fi
