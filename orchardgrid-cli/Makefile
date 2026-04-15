SHELL := /bin/bash

PREFIX ?= /usr/local
BIN_DIR := $(PREFIX)/bin
BUILD_DIR := .build/release
BINARY := $(BUILD_DIR)/og

.PHONY: help build release install uninstall test test-unit test-int test-all smoke-live clean format check-toolchain build-info

help: ## Show this help
	@awk 'BEGIN{FS=":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*##/ {printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── Build ───────────────────────────────────────────────────────────────────

check-toolchain: ## Verify the active Apple SDK meets FoundationModels' 26.4 floor
	@sdk=$$(xcrun --show-sdk-version 2>/dev/null || echo 0); \
	major=$${sdk%%.*}; minor=$${sdk#*.}; minor=$${minor%%.*}; \
	if [ -z "$$minor" ] || [ "$$minor" = "$$major" ]; then minor=0; fi; \
	if [ "$$major" -lt 26 ] || { [ "$$major" -eq 26 ] && [ "$$minor" -lt 4 ]; }; then \
		echo "error: og requires the macOS 26.4 SDK or newer (found $$sdk)." >&2; \
		echo "  xcode-select -p                  # show active developer dir" >&2; \
		echo "  sudo xcode-select -s <Xcode.app> # point at a 26.4+ Xcode" >&2; \
		exit 1; \
	fi

build-info: ## Regenerate Sources/ogKit/BuildInfo.swift (git commit + build date)
	@scripts/generate-build-info.sh

build: build-info ## Debug build
	swift build

release: check-toolchain build-info ## Release build
	swift build -c release

install: release ## Install release build (targets https://orchardgrid.com)
	install -d $(BIN_DIR)
	install -m 0755 $(BINARY) $(BIN_DIR)/og
	@echo "Installed PROD build: $(BIN_DIR)/og → https://orchardgrid.com"

install-dev: build ## Install debug build (targets http://localhost:4399)
	install -d $(BIN_DIR)
	install -m 0755 .build/debug/og $(BIN_DIR)/og
	@echo "Installed DEV build:  $(BIN_DIR)/og → http://localhost:4399"

uninstall: ## Remove installed binary
	rm -f $(BIN_DIR)/og

# ── Tests ───────────────────────────────────────────────────────────────────

test: test-unit test-int ## Run unit + integration tests

test-unit: build-info ## Swift Testing unit suite (no network, no binary needed)
	swift test

test-int: release ## pytest integration suite against a mock server
	python3 -m pytest Tests/integration -v

test-all: test ## Alias for test

smoke-live: release ## Live smoke test (requires OrchardGrid.app running)
	OG=$(BINARY) bash scripts/smoke-live.sh

# ── Maintenance ─────────────────────────────────────────────────────────────

format: ## Format Swift sources in place
	@command -v swift-format >/dev/null || { echo "swift-format not found — brew install swift-format"; exit 1; }
	swift-format format --in-place --recursive Sources Tests/ogKitTests

clean: ## Remove build artifacts
	swift package clean
	rm -rf .build
