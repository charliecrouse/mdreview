# mdreview

A native macOS app for reviewing Markdown and handing the review to a coding agent. The README covers what it does, how to build it and the full `make` table.

## Commands

- `make check` must pass before every commit. It runs swift-format and SwiftLint (`--strict`), the unit tests and Periphery.
- `make format` fixes layout. Run it before fixing lint by hand.
- `make uitest` runs when UI behavior changes.
- `make hooks` once per clone, so commits run `make lint`.

## Layout

- `Sources/MDReviewCore/`: rendering, the comment model and the export. No SwiftUI and no app state; it has unit tests.
- `Sources/mdreview/`: the SwiftUI app only.
  - `Views/`: SwiftUI views.
  - `Reader/`: AppKit bridges (the text view and the window glass).
- `Tests/MDReviewCoreTests/`: one `<Type>Tests.swift` per core type under test.
- `UITests/`: the end-to-end XCUITest.
- `project.yml` generates the gitignored Xcode project for the `.app`.

## Rules

- One primary type per file, and the file is named after it. Extensions go in `Type+Concern.swift`.
- Classes are `final`.
- No new dependency, package or tool without asking.
- No `swiftlint:disable` without a same-line reason, and never to get past a length or complexity rule: split the code instead.
- Delete dead code; don't comment it out. Unfinished work goes in the backlog, not in `TODO` comments.

## Comments

- Explain *why* or a non-obvious constraint. Never restate the code.
- Never narrate history or name tools, agents or other apps.
- Add doc comments only where the name can't say it.

## Docs

Any change to `make` targets, folders or user-visible behavior updates the README in the same commit.
