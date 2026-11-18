<div align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" height="128" alt="">
  <h1>mdreview</h1>
  <p>Review Markdown like a pull request, then hand the review to your coding agent.</p>
  <p>A native macOS app · macOS 26 or later · MIT</p>
</div>

![mdreview showing a rollout plan with two comments in the inspector](docs/images/screenshot.png)

## What it does

Open a `.md` file, select text in the rendered view and comment on it. Each comment is anchored to the source lines it covers, so an agent knows exactly where to look. Comments are saved as you go and come back when you reopen the file, even after a rename or move.

**Send to Agent** (⌘↩) batches every comment into one Markdown review: the file path, the line ranges, the quoted text and your note. It copies the review to the clipboard and saves it as `<name>-<hash>.review.md` in mdreview's own storage; the inspector shows the path. Paste the review into Claude Code, Codex or any other agent, or point the agent at the file.

An agent can skip the copy and paste. `mdreview plan.md` opens the file in the app (launching it if needed) and waits, the way `git commit` waits for its editor. When you press Send to Agent, the review is printed to the command's standard output and it exits 0. Closing the window, quitting the app or opening another file instead makes it exit 1 with a short message on standard error. Ctrl-C just stops the wait.

mdreview never writes into the folder that holds your Markdown. Everything it keeps lives in `~/Library/Application Support/mdreview/`: `Comments/` holds one JSON record per reviewed file, keyed by its path, `Reviews/` holds the sent reviews, and `Handoff/` holds the requests and answers of `mdreview` commands while they wait. A review looks like this:

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

The view follows the file. When an agent or an editor changes it, mdreview re-renders in place and each comment moves with its quoted text. A comment whose text was rewritten or removed stays in the inspector marked **Outdated**, and Send to Agent labels it so. If the file is deleted, the last version stays on screen until it comes back.

The window is glass: the desktop shows through, blurred, while the document sits on a dense frosted layer so text stays legible. Reduce Transparency or Increase Contrast make it opaque.

## Install

There's no prebuilt download yet; build it from source. You need macOS 26 (Tahoe) and Xcode 26 (Swift 6.2). From a clone of this repository (the file argument is optional):

```sh
swift run mdreview README.md
```

For a standalone app, run `make bootstrap` once, then `make app`. It builds an ad-hoc signed `build/mdreview.app` with its icon; drag it to `/Applications`.

To give agents the `mdreview` command, link the script inside the app into a folder on your `PATH`:

```sh
ln -s /Applications/mdreview.app/Contents/Resources/mdreview /usr/local/bin/mdreview
```

Then an agent runs `mdreview plan.md` and reads your review from the output.

## Usage

| Action | How |
|---|---|
| Open a file | ⌘O, or drop a `.md` file on the window |
| Comment on a selection | Select text, then press ⌥⌘M. Right-click → **Add Comment** and the toolbar button work too |
| Follow an agent's edits | Nothing to do: the open file reloads when it changes on disk, keeping your scroll position |
| Edit or delete a comment | Type in its card in the inspector, or click the trash icon. Changes save as you make them |
| Pick up a review later | Reopen the file; its saved comments come back |
| Jump to a comment or heading | Click it in the inspector or the sidebar |
| Show or hide the sidebar or comments | **View** menu, or the toolbar buttons |
| Send to Agent | ⌘↩, or the toolbar button. Overwrites the file's review in `~/Library/Application Support/mdreview/Reviews/` on each send; select the path in the inspector to copy it |
| Review for a waiting agent | The agent runs `mdreview <file>`; comment, then Send to Agent. Every `mdreview` command waiting on that file gets the review |

## Limitations

- A saved record that can't be read is moved aside as `<hash>.unreadable-<time>.json` in `Comments/`, and the file opens with no comments.
- Records for files you delete stay in `~/Library/Application Support/mdreview/` until you remove them.
- One file at a time, and the Markdown is read-only.
- A comment follows its quoted text as rendered. While the file is open, it shifts with edits around it. When an edit touches it, or one write changes text on both sides of it, it follows its quote only if the quote occurs exactly once in the changed text, both before and after the edit; otherwise it is marked outdated rather than moved to another copy. On reopen, a comment whose quote moved follows it only when the quote occurs exactly once; otherwise it is marked outdated. An outdated comment keeps the line numbers of the earlier version and stays outdated, across edits and reopens, until you delete it.
- Send to Agent is clipboard, file and the `mdreview` command; there are no agent plugins or MCP server.
- The `mdreview` command runs from the `.app` only, not from `swift run`.
- Tables render as simple tab-aligned rows (no borders, fixed 200 pt columns).
- Inline formatting that spans a soft line break (`**bold` on one line, `text**` on the next) renders literally. The renderer works line by line so every selection maps to exact source lines.
- The `.app` is ad-hoc signed for local use: no Developer ID, notarization or DMG.

## Development

On a fresh clone, run `make bootstrap`, then `make check`. Bootstrap needs [Homebrew](https://brew.sh) and installs the tools in `Brewfile`: [XcodeGen](https://github.com/yonaskolb/XcodeGen), [SwiftLint](https://github.com/realm/SwiftLint) and [Periphery](https://github.com/peripheryapp/periphery). `swift format` ships with the toolchain. `swift test` and the `.app` need full Xcode; the Command Line Tools alone can build and run.

| Target | What it does |
|---|---|
| `make bootstrap` | Install the `Brewfile` tools, check that `xcode-select` points at Xcode, then `make hooks` and `make project`. Safe to rerun |
| `make build` | `swift build` |
| `make run FILE=README.md` | Build and open a file (`FILE` is optional) |
| `make test` | `swift test`: the `MDReviewCoreTests` unit tests (Swift Testing) |
| `make lint` | `swift format lint --strict`, then `swiftlint lint --strict` (rules in `.swiftlint.yml`); fails on violations |
| `make format` | Rewrite sources with `swift format` |
| `make deadcode` | `periphery scan --strict`: fails on unused code (config in `.periphery.yml`) |
| `make docs-check` | Fails when this README's `make` table or Layout section disagrees with the Makefile or the tree |
| `make check` | `lint`, `test`, `deadcode`, then `docs-check`. Must pass before every commit |
| `make hooks` | One-time: use `.githooks/`, so every commit runs `make lint` |
| `make project` | Generate `mdreview.xcodeproj` from `project.yml` (the project is gitignored) |
| `make app` | Release build into `build/mdreview.app` |
| `make uitest` | Run the XCUITest in `UITests/`: open a file, toggle both sidebars, comment, Send to Agent, relaunch and find the comment again; then edit, delete and restore the file; then open a file an `mdreview` command asked for and answer it on Send |

Style lives in `.swift-format`, `.swiftlint.yml` and `.editorconfig`. Bundle settings and signing live in `project.yml`; open the generated project in Xcode to debug.

CI (`.github/workflows/ci.yml`) runs `make bootstrap` and `make check` on every pull request and every push to `main`.

`make uitest` drives the real app, so macOS must allow Automation Mode. Enable it once with `automationmodetool enable-automationmode-without-authentication` (it asks for an admin password), or approve the prompt Xcode shows on the first run. It isn't part of `make check`.

[AGENTS.md](AGENTS.md) has the house rules for contributors, human or agent.

## Layout

- `Sources/MDReviewCore/`
  - `MarkdownRenderer.swift`, `MarkdownRenderer+Inline.swift`: a line-oriented Markdown renderer. It tags every rendered character with the source line it came from.
  - `RenderedMarkdown.swift`: the renderer's output, its headings and the `.sourceLine` attribute.
  - `ReviewComment.swift`: the comment model.
  - `ReviewComment+Reanchor.swift`: moves a comment to its quoted text after the file changes, or marks it outdated.
  - `ReviewExport.swift`: the batched review an agent receives.
  - `ReviewStore.swift`: saved comments and sent reviews, kept in the app's Application Support folder.
  - `ReviewStore+Handoff.swift`: the request and answer files behind the `mdreview` command.
- `Sources/mdreview/`: the SwiftUI app.
  - `Main.swift`: starts the app, or the `mdreview` command when the bundled script passes `--wait`.
  - `MDReviewApp.swift`, `AppDelegate.swift`: the scene, menu commands, command-line file argument and opening files an `mdreview` command asks for.
  - `WaitCommand.swift`: the `mdreview <file>` command: opens the file in the app and waits for the review.
  - `ReviewModel.swift`: the open file, its comments (loaded and saved through the store), live reload and Send to Agent.
  - `FileWatcher.swift`: watches the open file, including atomic saves, deletion and recreation.
  - `Views/`: the split view with a glass sidebar (outline and comments) and the comment inspector.
  - `Reader/`: AppKit bridges: the `NSTextView` reader and the behind-window glass.
- `Tests/MDReviewCoreTests/`: unit tests, one file per type under test (`MarkdownRendererTests.swift`, `ReviewCommentTests.swift`, `ReviewExportTests.swift`, `ReviewStoreTests.swift`).
- `App/`: the app's asset catalog (icon) and `mdreview`, the command-line script the app bundles as a resource. `project.yml` builds the app from `Sources/mdreview` plus the `MDReviewCore` package product.
- `UITests/`: the end-to-end UI test.
- `.github/workflows/ci.yml`: the `check` job, which runs `make check` on GitHub Actions.
- `scripts/docs-check.sh`: the README freshness check behind `make docs-check`.

## License

MIT. See [LICENSE](LICENSE).
