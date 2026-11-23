SRC := Sources Tests UITests Package.swift
XCODE := xcodebuild -project mdreview.xcodeproj -scheme mdreview -derivedDataPath build/DerivedData

.PHONY: bootstrap build run test lint format deadcode docs-check check hooks project app install uitest

# The Command Line Tools can't run `swift test` or xcodebuild, so fail early unless Xcode is selected.
bootstrap:
	brew bundle --file=Brewfile
	@xcode-select -p | grep -q '\.app/' || { echo "bootstrap: xcode-select points at $$(xcode-select -p), not Xcode. Install Xcode 26, then run: sudo xcode-select -s /Applications/Xcode.app" >&2; exit 1; }
	$(MAKE) hooks project

build:
	swift build

# make run FILE=README.md
run:
	swift run mdreview $(FILE)

test:
	swift test

lint:
	swift format lint --strict -r $(SRC)
	swiftlint lint --strict --quiet

format:
	swift format format -i -r $(SRC)

deadcode:
	periphery scan --strict --quiet

docs-check:
	scripts/docs-check.sh

check: lint test deadcode docs-check

hooks:
	git config core.hooksPath .githooks

project:
	xcodegen generate

app: project
	$(XCODE) -configuration Release build
	rm -rf build/mdreview.app
	ditto build/DerivedData/Build/Products/Release/mdreview.app build/mdreview.app

install: app
	scripts/install.sh

# Needs macOS Automation Mode (`automationmodetool enable-automationmode-without-authentication`, once).
uitest: project
	$(XCODE) test
