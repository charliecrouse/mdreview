SRC := Sources Package.swift

.PHONY: build run test lint format check hooks

build:
	swift build

# make run FILE=README.md
run:
	swift run mdreview $(FILE)

# Swift Testing/XCTest need Xcode; the Command Line Tools run this self-check instead.
test:
	swift run mdreview-check

lint:
	swift format lint --strict -r $(SRC)

format:
	swift format format -i -r $(SRC)

check: lint test

hooks:
	git config core.hooksPath .githooks
