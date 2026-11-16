import Foundation
import MDReviewCore

// Self-check for the core logic: `swift run mdreview-check` (works with Command Line Tools or Xcode).
var failures = 0
@MainActor func check(_ ok: Bool, _ what: String = "", line: Int = #line) {
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

private let source = """
# Plan

Ship the importer behind a **feature flag**
and enable it for `internal` users first.

## Steps

- Add the flag
- [x] Backfill workspaces

```
mdreview send
```
"""

do { // rendered selections map back to source lines
    let rendered = MarkdownRenderer.render(source)
    let text = rendered.text.string as NSString

    check(rendered.headings.map(\.title) == ["Plan", "Steps"])
    check(rendered.headings.map(\.line) == [1, 6])
    // Markdown syntax is rendered away; content stays.
    check(!text.contains("**") && !text.contains("```") && !text.contains("# Plan"))
    check(text.contains("feature flag") && text.contains("☑"))

    func lines(_ needle: String) -> ClosedRange<Int>? {
        MarkdownRenderer.lineRange(of: text.range(of: needle), in: rendered.text)
    }
    check(lines("feature flag") == 3...3)
    check(lines("internal users") == 4...4, "second line of a joined paragraph")
    check(lines("flag and enable") == 3...4, "selection across the soft break")
    check(lines("Backfill") == 9...9)
    check(lines("mdreview send") == 12...12)

    let start = text.range(of: "Ship").location
    let span = NSRange(location: start, length: NSMaxRange(text.range(of: "Add the flag")) - start)
    check(MarkdownRenderer.lineRange(of: span, in: rendered.text) == 3...8)
    check(MarkdownRenderer.lineRange(of: NSRange(location: 0, length: 0), in: rendered.text) == nil)
    check(MarkdownRenderer.range(ofLine: 6, in: rendered.text).map { text.substring(with: $0) }?.hasPrefix("Steps") == true)
}

do { // tables render as tab-separated cells; the divider row is rendered away
    let table = MarkdownRenderer.render("| Action | How |\n|---|:--:|\n| Open | ⌘O |\n\nAfter the table.")
    let text = table.text.string as NSString
    check(!text.contains("|") && !text.contains("---"), "table syntax rendered away")
    check(text.contains("Action\tHow") && text.contains("Open\t⌘O"), "cells on tab stops")
    check(MarkdownRenderer.lineRange(of: text.range(of: "Open"), in: table.text) == 3...3, "row keeps its source line")
    check(MarkdownRenderer.lineRange(of: text.range(of: "After"), in: table.text) == 5...5)
}

do { // the review export carries path, lines, quote and comment
    let file = URL(fileURLWithPath: "/tmp/notes/plan.md")
    let comments = [
        ReviewComment(lines: 9...9, quote: "Backfill", text: "Which workspaces?", range: NSRange()),
        ReviewComment(lines: 3...4, quote: "feature flag\nand enable", text: "  Name the flag.  ", range: NSRange()),
    ]
    let review = ReviewExport.markdown(file: file, comments: comments)

    check(review.contains("File: `/tmp/notes/plan.md`"))
    check(review.contains("## 1. plan.md:3-4\n\n> feature flag\n> and enable\n\nName the flag.\n"))
    check(review.contains("## 2. plan.md:9\n\n> Backfill\n\nWhich workspaces?\n"))
    check(ReviewExport.reviewURL(for: file).path == "/tmp/notes/plan.review.md")
}

print(failures == 0 ? "mdreview-check: all checks passed" : "mdreview-check: \(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
