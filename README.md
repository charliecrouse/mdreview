# mdreview

A native macOS app for reviewing Markdown files and handing the review to a coding agent.

You open a `.md` file, select text in the rendered view and comment on it. Each comment is anchored to the source lines it covers. **Send to Agent** batches the comments into one Markdown review: file path, line ranges, the quoted text and your comment.

The design is "paper on glass". The sidebar, toolbar and comment inspector use system Liquid Glass, while the document itself sits on an opaque reading surface.

## Requirements

- macOS 26 (Tahoe) or later
- Swift 6.2: Xcode 26, or just the Command Line Tools (`xcode-select --install`)

## Build and run

```sh
swift build
swift run mdreview path/to/file.md
```

You can also run it without a file, then use **File → Open…** (⌘O) or drag a `.md` file onto the window. Try it on this README with `swift run mdreview README.md`.

Run the core self-check like this:

```sh
swift run mdreview-check
```

It checks rendered-to-source line mapping and the review export. It is a small executable rather than `swift test`, because the Command Line Tools ship Swift Testing without its Foundation overlay module, so `swift test` doesn't build there.

## Using it

| Action | How |
|---|---|
| Open a file | ⌘O, or drop a `.md` file on the window |
| Comment on a selection | Select text, then press ⌥⌘M. You can also right-click → **Add Comment**, or use the toolbar's comment button. |
| Edit or delete a comment | Type in its card in the inspector, or click the trash icon |
| Jump to a comment or heading | Click it in the inspector or the sidebar |
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
- `Sources/mdreview/MDReviewApp.swift`: the SwiftUI app. It has a split view with a glass sidebar (outline and comments), an opaque `NSTextView` reader, and a comment inspector.
- `Sources/mdreview-check/`: the self-check.

## Not yet

- Comments live in memory. The saved `.review.md` is the only thing written to disk, and it isn't loaded back.
- One file at a time, and the Markdown is read-only.
- No direct agent integrations; Send to Agent is clipboard plus file only.
- Inline formatting that spans a soft line break (for example `**bold` on one line and `text**` on the next) renders literally. The renderer works line by line so that every selection maps to exact source lines.
- It runs as a bare executable (`swift run`). There's no `.app` bundle or icon yet.
