SHELL := /bin/bash

PROJECT := orchardgrid-app.xcodeproj
SCHEME  := orchardgrid-app

XCB     := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -quiet
MAC_DST := generic/platform=macOS
IOS_DST := platform=iOS Simulator,name=iPhone 17

.PHONY: help build build-macos build-ios debug test test-macos test-ios format clean open release-notes

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

test: test-macos test-ios ## Run tests on macOS and iOS

test-macos: ## Run tests on macOS
	$(XCB) -configuration Debug -destination 'platform=macOS' test

test-ios: ## Run tests on iPhone 17 simulator
	$(XCB) -configuration Debug -destination '$(IOS_DST)' test

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
