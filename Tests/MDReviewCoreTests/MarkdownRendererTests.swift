import AppKit
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

/// A rendered document with helpers to find text in it and the source lines that text came from.
private struct Rendered {
    let rendered: RenderedMarkdown
    var text: NSString { rendered.text.string as NSString }

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

    func font(of needle: String) -> NSFont? { attribute(.font, of: needle) as? NSFont }

    func traits(of needle: String) -> NSFontDescriptor.SymbolicTraits {
        font(of: needle)?.fontDescriptor.symbolicTraits ?? []
    }

    func blocks(of needle: String) -> [NSTextBlock] {
        (attribute(.paragraphStyle, of: needle) as? NSParagraphStyle)?.textBlocks ?? []
    }

    /// Every rendered character maps to a source line.
    var everyCharacterHasALine: Bool {
        var all = true
        rendered.text.enumerateAttribute(.sourceLine, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value == nil { all = false }
        }
        return all
    }
}

@Suite struct RenderedSelectionMapsToSourceLines {
    private let doc = Rendered(source)

    @Test func headings() {
        #expect(doc.rendered.headings.map(\.title) == ["Plan", "Steps"])
        #expect(doc.rendered.headings.map(\.line) == [1, 6])
    }

    @Test func syntaxIsRenderedAwayAndContentStays() {
        #expect(!doc.text.contains("**") && !doc.text.contains("```") && !doc.text.contains("# Plan"))
        #expect(doc.text.contains("feature flag") && doc.text.contains("☑"))
        #expect(doc.everyCharacterHasALine)
    }

    @Test func selectionsMapToLines() {
        #expect(doc.lines("feature flag") == 3...3)
        #expect(doc.lines("internal users") == 4...4, "second line of a joined paragraph")
        #expect(doc.lines("flag and enable") == 3...4, "selection across the soft break")
        #expect(doc.lines("Backfill") == 9...9)
        #expect(doc.lines("mdreview send") == 12...12)
    }

    @Test func spansAndEdges() {
        let start = doc.text.range(of: "Ship").location
        let span = NSRange(location: start, length: NSMaxRange(doc.text.range(of: "Add the flag")) - start)
        #expect(MarkdownRenderer.lineRange(of: span, in: doc.rendered.text) == 3...8)
        #expect(MarkdownRenderer.lineRange(of: NSRange(location: 0, length: 0), in: doc.rendered.text) == nil)
        let steps = MarkdownRenderer.range(ofLine: 6, in: doc.rendered.text).map { doc.text.substring(with: $0) }
        #expect(steps?.hasPrefix("Steps") == true)
    }
}

@Test func atxAndSetextHeadings() {
    let doc = Rendered("Title\n=====\n\nSection\n-------\n\n### Closed ###\n")
    #expect(doc.rendered.headings.map(\.title) == ["Title", "Section", "Closed"])
    #expect(doc.rendered.headings.map(\.level) == [1, 2, 3])
    #expect(doc.rendered.headings.map(\.line) == [1, 4, 7])
    #expect(!doc.text.contains("=") && !doc.text.contains("-") && !doc.text.contains("#"))
    #expect(doc.traits(of: "Title").contains(.bold))
}

@Test func softAndHardBreaks() {
    let doc = Rendered("one\ntwo  \nthree\\\nfour")
    #expect(doc.text.hasPrefix("one two\u{2028}three\u{2028}four"))
    #expect(doc.lines("two") == 2...2 && doc.lines("three") == 3...3 && doc.lines("four") == 4...4)
}

@Test func inlineStylesSpanSoftBreaks() {
    let doc = Rendered("**bold\nacross** and *it\nalic* and ~~gone\nnow~~ and `co\nde`")
    #expect(!doc.text.contains("*") && !doc.text.contains("~") && !doc.text.contains("`"))
    #expect(doc.traits(of: "across").contains(.bold))
    #expect(doc.traits(of: "alic").contains(.italic))
    #expect(doc.attribute(.strikethroughStyle, of: "now") != nil)
    #expect(doc.traits(of: "co de").contains(.monoSpace))
    #expect(doc.lines("across") == 2...2)
}

@Test func linksResolveAgainstTheFilesFolder() {
    let folder = URL(fileURLWithPath: "/tmp/docs/", isDirectory: true)
    let doc = Rendered(
        "[next](other.md) and [site][ref] and <https://example.com/a> and https://bare.example.org and "
            + "[top](#plan) and README.md\n\n[ref]: https://example.com/ref",
        baseURL: folder)
    #expect(doc.attribute(.link, of: "next") as? URL == URL(fileURLWithPath: "/tmp/docs/other.md"))
    #expect((doc.attribute(.link, of: "site") as? URL)?.absoluteString == "https://example.com/ref")
    #expect((doc.attribute(.link, of: "https://example.com/a") as? URL)?.absoluteString == "https://example.com/a")
    #expect((doc.attribute(.link, of: "https://bare") as? URL)?.host() == "bare.example.org")
    #expect((doc.attribute(.link, of: "top") as? URL)?.absoluteString == "#plan")
    #expect(doc.attribute(.link, of: "README.md") == nil, "a filename isn't a link")
    #expect(!doc.text.contains("[ref]"), "the reference definition renders away")
}

@Test func localImagesAttachAndRemoteOnesShowAltText() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let image = NSImage(size: NSSize(width: 1280, height: 20), flipped: false) { _ in true }
    let png = try #require(
        image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
    try png.write(to: folder.appending(path: "shot.png"))

    let doc = Rendered("![local](shot.png)\n\n![remote](https://example.com/x.png)", baseURL: folder)
    let attachment = try #require(doc.attribute(.attachment, of: "\u{FFFC}") as? NSTextAttachment)
    #expect(attachment.bounds.width == 640, "scaled to the reading measure")
    #expect(doc.lines("\u{FFFC}") == 1...1)
    #expect(doc.text.contains("[remote]") && !doc.text.contains("local"))
    #expect(doc.lines("remote") == 3...3)
}

@Test func nestedQuotesNestTheirBars() {
    let doc = Rendered("> outer\n> > inner\n>\n> back *out*\n\nAfter.")
    #expect(!doc.text.contains(">") && !doc.text.contains("*"))
    #expect(doc.blocks(of: "outer").count == 1 && doc.blocks(of: "inner").count == 2)
    #expect(doc.blocks(of: "back").count == 1 && doc.blocks(of: "After").isEmpty)
    #expect(doc.lines("outer") == 1...1 && doc.lines("inner") == 2...2 && doc.lines("back") == 4...4)
}

@Test func listsNestContinueAndNumber() {
    let doc = Rendered(
        """
        3. third
           continues here
        4. fourth

           second paragraph
           - nested
             - deeper
        - [ ] open task
        """)
    #expect(doc.text.contains("3.\tthird continues here") && doc.text.contains("4.\tfourth"))
    #expect(doc.text.contains("•\tnested") || doc.text.contains("◦\tnested"))
    #expect(doc.text.contains("▪\tdeeper") || doc.text.contains("◦\tdeeper"))
    #expect(doc.text.contains("☐\topen task"))
    #expect(doc.lines("continues") == 2...2 && doc.lines("second paragraph") == 5...5 && doc.lines("deeper") == 7...7)
    let indent = { (needle: String) in
        (doc.attribute(.paragraphStyle, of: needle) as? NSParagraphStyle)?.headIndent ?? 0
    }
    #expect(indent("third") < indent("nested") && indent("nested") < indent("deeper"))
    #expect(indent("second paragraph") == indent("third"), "a continuation block lines up with its item")
}

@Test func fencedAndIndentedCode() {
    let doc = Rendered("~~~swift\nlet a = 1\n\nlet b = 2\n~~~\n\n    indented\n    more\n\n```\nnot `closed by` ~~~\n")
    #expect(doc.text.contains("swift\nlet a = 1\n\nlet b = 2\n"), "language label, then code with its blank line")
    #expect(doc.lines("swift") == 1...1 && doc.lines("let a") == 2...2 && doc.lines("let b") == 4...4)
    #expect(doc.lines("indented") == 7...7 && doc.lines("more") == 8...8)
    #expect(doc.text.contains("not `closed by` ~~~"), "a fence only closes on its own character")
    #expect(doc.traits(of: "let a").contains(.monoSpace) && doc.traits(of: "indented").contains(.monoSpace))
    #expect(doc.blocks(of: "let a").first?.backgroundColor != nil)
}

@Test func thematicBreaks() {
    let doc = Rendered("Above\n\n***\n\n- - -\n\nBelow")
    #expect(doc.text.components(separatedBy: "· · ·").count == 3)
    #expect(MarkdownRenderer.range(ofLine: 3, in: doc.rendered.text).map { doc.text.substring(with: $0) } == "· · ·\n")
}

@Test func tablesUseTextTableCells() {
    let doc = Rendered("| Action | How |\n|---|:--:|\n| Open a file | ⌘O |\n| Send | ⌘↩ |\n\nAfter the table.")
    #expect(!doc.text.contains("|") && !doc.text.contains("---"), "table syntax rendered away")
    let cell = doc.blocks(of: "Open a file").last as? NSTextTableBlock
    #expect(cell?.startingRow == 1 && cell?.startingColumn == 0)
    #expect((doc.blocks(of: "⌘↩").last as? NSTextTableBlock)?.startingColumn == 1)
    #expect(cell?.table === (doc.blocks(of: "Action").last as? NSTextTableBlock)?.table, "one table")
    #expect(doc.traits(of: "Action").contains(.bold), "header row")
    #expect((doc.attribute(.paragraphStyle, of: "⌘O") as? NSParagraphStyle)?.alignment == .center)
    #expect(doc.lines("Open") == 3...3 && doc.lines("Send") == 4...4 && doc.lines("After") == 6...6)
    #expect(doc.blocks(of: "After").isEmpty)
    let width = { (needle: String) in (doc.blocks(of: needle).last as? NSTextTableBlock)?.value(for: .width) ?? 0 }
    #expect(width("Open a file") > width("⌘O"), "columns are measured, not fixed")
    #expect(width("Open a file") == width("Send"), "a column shares one width")
}

@Test func footnotesBecomeSuperscriptLabels() {
    let doc = Rendered(
        "Claim[^1] and more[^note].\n\n[^1]: First source.\n[^note]: Second source.\n\n`[^1]` stays code.")
    #expect(doc.text.hasPrefix("Claim1 and morenote."))
    #expect((doc.attribute(.baselineOffset, of: "1 and") as? CGFloat ?? 0) > 0)
    #expect(doc.text.contains("1 First source.\nnote Second source."))
    #expect(doc.lines("First source") == 3...3 && doc.lines("Second source") == 4...4)
    #expect(doc.text.contains("[^1] stays code"))
}

@Test func footnoteDefinitionReferencingAnotherEndsCleanlyAtEndOfFile() {
    let doc = Rendered("A[^1] B[^2]\n\n[^2]: Other.\n[^1]: see [^2]")
    #expect(doc.text.contains("1 see 2"))
}

@Test func rawHTMLShowsAsCodeStyledSource() {
    let doc = Rendered("<details>\n<summary>More</summary>\n</details>\n\nInline <kbd>K</kbd> here.")
    #expect(doc.text.contains("<details>\n<summary>More</summary>\n</details>"))
    #expect(doc.traits(of: "<summary>").contains(.monoSpace) && doc.lines("<summary>") == 2...2)
    #expect(doc.traits(of: "<kbd>").contains(.monoSpace))
}

@Test func frontMatterIsAMutedBlockNotHeadings() {
    let doc = Rendered("---\ntitle: Plan\ntags: [a]\n---\n\n# Real\n")
    #expect(doc.rendered.headings.map(\.title) == ["Real"])
    #expect(doc.text.hasPrefix("title: Plan\ntags: [a]\n") && !doc.text.contains("---"))
    #expect(doc.lines("title") == 2...2 && doc.lines("tags") == 3...3 && doc.lines("Real") == 6...6)
    #expect(doc.attribute(.foregroundColor, of: "title") as? NSColor == .secondaryLabelColor)
}

@Test func everyConstructTagsEveryCharacter() {
    let doc = Rendered(
        "---\na: b\n---\n# H\n\n> q\n\n- [x] t\n  1. n\n\n```\nc\n```\n\n"
            + "| a |\n|---|\n| b |\n\n<div>\n\nx[^1]\n\n[^1]: y\n![gone](missing.png)\n")
    #expect(doc.everyCharacterHasALine)
}

@Test func quoteIsTrimmedAndRefusesWhitespaceOnlySelections() {
    let doc = Rendered("First.\n\nSecond.")
    let gap = NSRange(location: NSMaxRange(doc.text.range(of: "First.")), length: 1)
    #expect(MarkdownRenderer.quote(of: gap, in: doc.rendered.text) == nil)
    let padded = NSRange(location: 0, length: doc.text.range(of: "Second.").location)
    #expect(MarkdownRenderer.quote(of: padded, in: doc.rendered.text) == "First.")
    #expect(MarkdownRenderer.quote(of: NSRange(location: 0, length: doc.text.length + 1), in: doc.rendered.text) == nil)
}

@Test func tableColumnSpansKeepLaterCellsInTheirColumns() {
    let doc = Rendered("| a | b | c | d |\n|---|---|---|---|\n| x ||| y |\n")
    #expect((doc.blocks(of: "x").last as? NSTextTableBlock)?.columnSpan == 3)
    #expect((doc.blocks(of: "y").last as? NSTextTableBlock)?.startingColumn == 3)
    #expect(doc.everyCharacterHasALine)
}

@Test(arguments: [
    "", "\n", "\r", "\r\r# Mac line ends\r", "\0", "\u{FEFF}# BOM", "---", "---\n", "---\n---", "---\n---\n---",
    "---\nunclosed: front matter\n", "...\n", "| a |\n|---|\n| b | c | d |", "|a|\n|-|\n|^|\n|x|", "| a | b |\n|---|",
    "[^a]:", "[^a]:\n[^b]:", "```\n[^a]: x\n```", "![](missing.png)", "![]()", "[]()", "<", "```", "~~~\n",
    "1. \n2.", "- [ ]", "    ", "# ", "e\u{301}\u{301}\u{301} 👩‍👩‍👧 é",
    String(repeating: "> ", count: 20_000) + "deep", String(repeating: "- ", count: 300) + "deep",
    String(repeating: "*", count: 4000) + "a" + String(repeating: "*", count: 4000),
    String(repeating: "*", count: 5000), String(repeating: "[", count: 5000),
    String(repeating: "[", count: 5000) + "a" + String(repeating: "](b)", count: 5000),
    String(repeating: "- > ", count: 2000) + "deep",
    String(repeating: "x", count: 200_000),
    String(repeating: "| a ", count: 300) + "|\n" + String(repeating: "|-", count: 300) + "|",
])
@MainActor  // the app renders on the main thread, whose stack is far deeper than a test thread's
func extremeAndMalformedMarkdownRenders(source: String) {
    let doc = Rendered(source)
    #expect(doc.everyCharacterHasALine)
}
