SRC := Sources Tests UITests Package.swift
XCODE := xcodebuild -project mdreview.xcodeproj -scheme mdreview -derivedDataPath build/DerivedData

.PHONY: build run test lint format deadcode docs-check check hooks project app uitest

build:
	swift build

# make run FILE=README.md
run:
	swift run mdreview $(FILE)

test:
	swift test

# Needs SwiftLint: brew install swiftlint
lint:
	swift format lint --strict -r $(SRC)
	swiftlint lint --strict --quiet

format:
	swift format format -i -r $(SRC)

# Needs Periphery: brew install periphery
deadcode:
	periphery scan --strict --quiet

docs-check:
	scripts/docs-check.sh

check: lint test deadcode docs-check

hooks:
	git config core.hooksPath .githooks

# Needs XcodeGen: brew install xcodegen
project:
	xcodegen generate

app: project
	$(XCODE) -configuration Release build
	rm -rf build/mdreview.app
	ditto build/DerivedData/Build/Products/Release/mdreview.app build/mdreview.app

# Needs macOS Automation Mode (`automationmodetool enable-automationmode-without-authentication`, once).
uitest: project
	$(XCODE) test
