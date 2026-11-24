import AppKit
import MDReviewCore
import Testing

/// Whether every character carries the source line it came from, which every selection relies on.
func everyCharacterHasALine(_ text: NSAttributedString) -> Bool {
    var all = true
    text.enumerateAttribute(.sourceLine, in: NSRange(location: 0, length: text.length)) { value, _, _ in
        if value == nil { all = false }
    }
    return all
}

/// A rendered document, with lookups of the text, lines and attributes at the first copy of a needle.
struct Rendered {
    let rendered: RenderedMarkdown
    var string: String { rendered.text.string }
    var text: NSString { string as NSString }

    init(_ source: String, baseURL: URL? = nil) {
        rendered = MarkdownRenderer.render(source, baseURL: baseURL)
    }

    func lines(_ needle: String) -> ClosedRange<Int>? {
        let range = text.range(of: needle)
        return range.location == NSNotFound ? nil : MarkdownRenderer.lineRange(of: range, in: rendered.text)
    }

    func attribute(_ key: NSAttributedString.Key, of needle: String) -> Any? {
        let range = text.range(of: needle)
        return range.location == NSNotFound
            ? nil : rendered.text.attribute(key, at: range.location, effectiveRange: nil)
    }

    func traits(of needle: String) -> NSFontDescriptor.SymbolicTraits {
        (attribute(.font, of: needle) as? NSFont)?.fontDescriptor.symbolicTraits ?? []
    }

    func paragraph(of needle: String) -> NSParagraphStyle? {
        attribute(.paragraphStyle, of: needle) as? NSParagraphStyle
    }

    func blocks(of needle: String) -> [NSTextBlock] { paragraph(of: needle)?.textBlocks ?? [] }

    func cell(of needle: String) -> NSTextTableBlock? { blocks(of: needle).last as? NSTextTableBlock }
}

@Test func untaggedTextIsReportedAsMissingLines() {
    let untagged = NSAttributedString(string: "Plain")

    let tagged = everyCharacterHasALine(untagged)

    #expect(!tagged)
}

// MARK: - Mapping a selection to source lines

private let plan = """
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

@Test func planRendersWithoutItsMarkdownSyntax() {
    let doc = Rendered(plan)

    #expect(
        doc.string
            == "Plan\nShip the importer behind a feature flag and enable it for internal users first.\nSteps\n"
            + "•\tAdd the flag\n☑\tBackfill workspaces\nmdreview send\n\n")
}

@Test func everyCharacterOfAPlanMapsToASourceLine() {
    let doc = Rendered(plan)

    #expect(everyCharacterHasALine(doc.rendered.text))
}

@Test(arguments: [
    ("feature flag", 3...3), ("internal users", 4...4), ("flag and enable", 3...4), ("Backfill", 9...9),
    ("mdreview send", 12...12),
])
func selectionMapsToTheSourceLinesItCameFrom(needle: String, lines: ClosedRange<Int>) {
    let doc = Rendered(plan)

    let mapped = doc.lines(needle)

    #expect(mapped == lines)
}

@Test func selectionAcrossBlocksMapsToEveryLineItSpans() {
    let doc = Rendered(plan)
    let start = doc.text.range(of: "Ship").location
    let span = NSRange(location: start, length: NSMaxRange(doc.text.range(of: "Add the flag")) - start)

    let lines = MarkdownRenderer.lineRange(of: span, in: doc.rendered.text)

    #expect(lines == 3...8)
}

@Test func emptySelectionMapsToNoLines() {
    let doc = Rendered(plan)

    let lines = MarkdownRenderer.lineRange(of: NSRange(location: 0, length: 0), in: doc.rendered.text)

    #expect(lines == nil)
}

@Test func sourceLineMapsToItsRenderedText() {
    let doc = Rendered(plan)

    let range = MarkdownRenderer.range(ofLine: 6, in: doc.rendered.text)

    #expect(range.map(doc.text.substring(with:)) == "Steps\n")
}

@Test func quoteIsTrimmedOfSurroundingWhitespace() {
    let doc = Rendered("First.\n\nSecond.")
    let padded = NSRange(location: 0, length: doc.text.range(of: "Second.").location)

    let quote = MarkdownRenderer.quote(of: padded, in: doc.rendered.text)

    #expect(quote == "First.")
}

@Test func whitespaceOnlySelectionHasNoQuote() {
    let doc = Rendered("First.\n\nSecond.")
    let gap = NSRange(location: NSMaxRange(doc.text.range(of: "First.")), length: 1)

    let quote = MarkdownRenderer.quote(of: gap, in: doc.rendered.text)

    #expect(quote == nil)
}

@Test func selectionPastTheEndHasNoQuote() {
    let doc = Rendered("First.\n\nSecond.")

    let quote = MarkdownRenderer.quote(of: NSRange(location: 0, length: doc.text.length + 1), in: doc.rendered.text)

    #expect(quote == nil)
}

// MARK: - Headings and breaks

@Test func headingsListTheirTitlesLevelsAndLines() {
    let doc = Rendered("Title\n=====\n\nSection\n-------\n\n### Closed ###\n")

    let headings = doc.rendered.headings

    #expect(headings.map(\.title) == ["Title", "Section", "Closed"])
    #expect(headings.map(\.level) == [1, 2, 3])
    #expect(headings.map(\.line) == [1, 4, 7])
}

@Test func headingMarkersRenderAway() {
    let doc = Rendered("Title\n=====\n\nSection\n-------\n\n### Closed ###\n")

    #expect(doc.string == "Title\nSection\nClosed\n")
}

@Test func headingsRenderBold() {
    let doc = Rendered("Title\n=====\n")

    #expect(doc.traits(of: "Title").contains(.bold))
}

@Test func softBreaksJoinLinesAndHardBreaksKeepThem() {
    let doc = Rendered("one\ntwo  \nthree\\\nfour")

    #expect(doc.text.hasPrefix("one two\u{2028}three\u{2028}four"))
}

@Test(arguments: [("two", 2...2), ("three", 3...3), ("four", 4...4)])
func brokenLinesMapToTheirOwnSourceLines(needle: String, lines: ClosedRange<Int>) {
    let doc = Rendered("one\ntwo  \nthree\\\nfour")

    #expect(doc.lines(needle) == lines)
}

@Test func thematicBreaksRenderAsDots() {
    let doc = Rendered("Above\n\n***\n\n- - -\n\nBelow")

    #expect(doc.string == "Above\n· · ·\n· · ·\nBelow\n")
}

@Test func thematicBreakMapsToItsSourceLine() {
    let doc = Rendered("Above\n\n***\n\nBelow")

    let range = MarkdownRenderer.range(ofLine: 3, in: doc.rendered.text)

    #expect(range.map(doc.text.substring(with:)) == "· · ·\n")
}

// MARK: - Inline styles

@Test func inlineMarkersRenderAwayAcrossSoftBreaks() {
    let doc = Rendered("**bold\nacross** and *it\nalic* and ~~gone\nnow~~ and `co\nde`")

    #expect(doc.string == "bold across and it alic and gone now and co de\n")
}

@Test(arguments: [
    ("across", NSFontDescriptor.SymbolicTraits.bold), ("alic", .italic), ("co de", .monoSpace),
])
func inlineStyleSpansASoftBreak(needle: String, trait: NSFontDescriptor.SymbolicTraits) {
    let doc = Rendered("**bold\nacross** and *it\nalic* and `co\nde`")

    #expect(doc.traits(of: needle).contains(trait))
}

@Test func strikethroughSpansASoftBreak() {
    let doc = Rendered("~~gone\nnow~~")

    #expect(doc.attribute(.strikethroughStyle, of: "now") != nil)
}

@Test func styledTextAfterASoftBreakMapsToItsOwnLine() {
    let doc = Rendered("**bold\nacross**")

    #expect(doc.lines("across") == 2...2)
}

@Test func rawHTMLShowsAsCodeStyledSource() {
    let doc = Rendered("<details>\n<summary>More</summary>\n</details>\n\nInline <kbd>K</kbd> here.")

    #expect(doc.text.contains("<details>\n<summary>More</summary>\n</details>"))
    #expect(doc.traits(of: "<summary>").contains(.monoSpace))
    #expect(doc.traits(of: "<kbd>").contains(.monoSpace))
}

@Test func rawHTMLBlockKeepsItsSourceLines() {
    let doc = Rendered("<details>\n<summary>More</summary>\n</details>")

    #expect(doc.lines("<summary>") == 2...2)
}
