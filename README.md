# mdreview

A native macOS app for reviewing Markdown files and handing the review to a coding agent.

You open a `.md` file, select text in the rendered view and comment on it. Each comment is anchored to the source lines it covers. **Send to Agent** batches the comments into one Markdown review: file path, line ranges, the quoted text and your comment.

The whole window is glass. A behind-window material lets the desktop show through, blurred, and the native sidebar floats on top of it. The document sits on a dense frosted layer, so body text stays legible over busy wallpapers. Reduce Transparency or Increase Contrast make it opaque.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 (Swift 6.2). `swift test` and the `.app` need full Xcode; the Command Line Tools alone can build and run
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the `.app`: `brew install xcodegen`

## Build and run

```sh
swift build
swift run mdreview path/to/file.md
```

You can also run it without a file, then use **File → Open…** (⌘O) or drag a `.md` file onto the window. Try it on this README with `swift run mdreview README.md`.

`make app` builds a signed (ad-hoc) Release `build/mdreview.app` with its icon.

## Development

Plain `make`. `swift format` ships with the Swift 6.2 toolchain; the Xcode targets also need XcodeGen.

| Target | What it does |
|---|---|
| `make build` | `swift build` |
| `make run FILE=README.md` | Build and open a file (`FILE` is optional) |
| `make test` | `swift test`: the `MDReviewCoreTests` unit tests (Swift Testing) |
| `make lint` | `swift format lint --strict`; fails on violations |
| `make format` | Rewrite sources with `swift format` |
| `make check` | `lint` then `test` |
| `make hooks` | One-time: use `.githooks/`, so every commit runs `make lint` |
| `make project` | Generate `mdreview.xcodeproj` from `project.yml` (the project is gitignored) |
| `make app` | Release build into `build/mdreview.app` |
| `make uitest` | Run the XCUITest in `UITests/`: open a file, toggle both sidebars, comment, Send to Agent |

Style lives in `.swift-format` and `.editorconfig`. The app's bundle settings and signing live in `project.yml`; open the generated project in Xcode to debug.

`make uitest` drives the real app, so macOS must allow Automation Mode. Enable it once with `automationmodetool enable-automationmode-without-authentication` (it asks for an admin password), or approve the prompt Xcode shows on the first run. It isn't part of `make check`.

## Using it

| Action | How |
|---|---|
| Open a file | ⌘O, or drop a `.md` file on the window |
| Comment on a selection | Select text, then press ⌥⌘M. You can also right-click → **Add Comment**, or use the toolbar's comment button. |
| Edit or delete a comment | Type in its card in the inspector, or click the trash icon |
| Jump to a comment or heading | Click it in the inspector or the sidebar |
| Show or hide the sidebar or comments | **View** menu, or the toolbar buttons |
| Send to Agent | Press ⌘↩ or use the toolbar button |

**Send to Agent** is a local handoff in this version. It copies the review to the clipboard and also saves it next to the file as `<name>.review.md`. The saved file is overwritten on each send. Paste the review into Claude Code, Codex or another agent, or point the agent at the saved file:

```markdown
# Review of plan.md

File: `/path/to/plan.md`
Comments: 2. Line numbers refer to the file above. Address each comment.

## 1. plan.md:3-4

> feature flag and enable

Name the actual flag.

## 2. plan.md:16

> Flip the default after one week

What's the rollback?
```

## Layout

- `Sources/MDReviewCore/`
  - `Markdown.swift`: a line-oriented Markdown renderer. It tags every rendered character with the source line it came from.
  - `Review.swift`: the comment model and the review export.
- `Sources/mdreview/`: the SwiftUI app.
  - `MDReviewApp.swift`, `AppDelegate.swift`: the scene, menu commands and command-line file argument.
  - `ReviewModel.swift`: the open file, its comments and Send to Agent.
  - `Views/`: the split view with a glass sidebar (outline and comments) and the comment inspector.
  - `Reader/`: AppKit bridges: the `NSTextView` reader and the behind-window glass.
- `Tests/MDReviewCoreTests/`: unit tests for the renderer and the review export.
- `App/`: the app's asset catalog (icon). `project.yml` builds the app from `Sources/mdreview` plus the `MDReviewCore` package product.
- `UITests/`: the end-to-end UI test.

## Not yet

- Comments live in memory. The saved `.review.md` is the only thing written to disk, and it isn't loaded back.
- One file at a time, and the Markdown is read-only.
- No direct agent integrations; Send to Agent is clipboard plus file only.
- Tables render as simple tab-aligned rows (no borders, fixed 200 pt columns).
- Inline formatting that spans a soft line break (for example `**bold` on one line and `text**` on the next) renders literally. The renderer works line by line so that every selection maps to exact source lines.
- The `.app` is ad-hoc signed for local use only: no Developer ID, notarization or DMG.
