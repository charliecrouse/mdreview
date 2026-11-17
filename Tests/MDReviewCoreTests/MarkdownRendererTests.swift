import Foundation
import MDReviewCore
import Testing

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

@Suite struct RenderedSelectionMapsToSourceLines {
    let rendered = MarkdownRenderer.render(source)
    var text: NSString { rendered.text.string as NSString }

    func lines(_ needle: String) -> ClosedRange<Int>? {
        MarkdownRenderer.lineRange(of: text.range(of: needle), in: rendered.text)
    }

    @Test func headings() {
        #expect(rendered.headings.map(\.title) == ["Plan", "Steps"])
        #expect(rendered.headings.map(\.line) == [1, 6])
    }

    @Test func syntaxIsRenderedAwayAndContentStays() {
        #expect(!text.contains("**") && !text.contains("```") && !text.contains("# Plan"))
        #expect(text.contains("feature flag") && text.contains("☑"))
    }

    @Test func selectionsMapToLines() {
        #expect(lines("feature flag") == 3...3)
        #expect(lines("internal users") == 4...4, "second line of a joined paragraph")
        #expect(lines("flag and enable") == 3...4, "selection across the soft break")
        #expect(lines("Backfill") == 9...9)
        #expect(lines("mdreview send") == 12...12)
    }

    @Test func spansAndEdges() {
        let start = text.range(of: "Ship").location
        let span = NSRange(location: start, length: NSMaxRange(text.range(of: "Add the flag")) - start)
        #expect(MarkdownRenderer.lineRange(of: span, in: rendered.text) == 3...8)
        #expect(MarkdownRenderer.lineRange(of: NSRange(location: 0, length: 0), in: rendered.text) == nil)
        #expect(
            MarkdownRenderer.range(ofLine: 6, in: rendered.text).map { text.substring(with: $0) }?.hasPrefix("Steps")
                == true)
    }
}

@Test func tablesRenderAsTabSeparatedCells() {
    let table = MarkdownRenderer.render("| Action | How |\n|---|:--:|\n| Open | ⌘O |\n\nAfter the table.")
    let text = table.text.string as NSString
    #expect(!text.contains("|") && !text.contains("---"), "table syntax rendered away")
    #expect(text.contains("Action\tHow") && text.contains("Open\t⌘O"), "cells on tab stops")
    #expect(
        MarkdownRenderer.lineRange(of: text.range(of: "Open"), in: table.text) == 3...3, "row keeps its source line")
    #expect(MarkdownRenderer.lineRange(of: text.range(of: "After"), in: table.text) == 5...5)
}
