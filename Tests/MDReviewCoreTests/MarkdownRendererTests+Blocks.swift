import AppKit
import MDReviewCore
import Testing

// MARK: - Links and images

@Test(arguments: [
    ("[next](other.md)", "next", "file:///tmp/docs/other.md"),
    ("[site][ref]\n\n[ref]: https://example.com/ref", "site", "https://example.com/ref"),
    ("<https://example.com/a>", "https://example.com/a", "https://example.com/a"),
    ("see https://bare.example.org now", "https://bare", "https://bare.example.org"),
    ("[top](#plan)", "top", "#plan"),
])
func linkResolvesAgainstTheFilesFolder(source: String, needle: String, target: String) {
    let doc = Rendered(source, baseURL: URL(fileURLWithPath: "/tmp/docs/", isDirectory: true))

    let link = doc.attribute(.link, of: needle) as? URL

    #expect(link?.absoluteString == target)
}

@Test func bareFilenameIsNotALink() {
    let doc = Rendered("See README.md first.")

    #expect(doc.attribute(.link, of: "README.md") == nil)
}

@Test func referenceDefinitionRendersAway() {
    let doc = Rendered("[site][ref]\n\n[ref]: https://example.com/ref")

    #expect(doc.string == "site\n")
}

@Test func localImageIsAttachedAtTheReadingMeasure() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let image = NSImage(size: NSSize(width: 1280, height: 20), flipped: false) { _ in true }
    let png = try #require(
        image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
    try png.write(to: folder.appending(path: "shot.png"))

    let doc = Rendered("Intro.\n\n![local](shot.png)", baseURL: folder)

    let attachment = try #require(doc.attribute(.attachment, of: "\u{FFFC}") as? NSTextAttachment)
    #expect(attachment.bounds.width == 640)
    #expect(doc.lines("\u{FFFC}") == 3...3)
    #expect(!doc.text.contains("local"))
}

@Test func remoteImageShowsItsAltText() {
    let doc = Rendered("Intro.\n\n![remote](https://example.com/x.png)")

    #expect(doc.string == "Intro.\n[remote]\n")
    #expect(doc.lines("remote") == 3...3)
}

// MARK: - Quotes and lists

@Test(arguments: [("outer", 1), ("inner", 2), ("back", 1), ("After", 0)])
func quoteNestsOneBarPerLevel(needle: String, bars: Int) {
    let doc = Rendered("> outer\n> > inner\n>\n> back *out*\n\nAfter.")

    #expect(doc.blocks(of: needle).count == bars)
}

@Test func quoteMarkersRenderAway() {
    let doc = Rendered("> outer\n> > inner\n>\n> back *out*\n\nAfter.")

    #expect(!doc.text.contains(">"))
}

@Test(arguments: [("outer", 1...1), ("inner", 2...2), ("back", 4...4)])
func quotedLineMapsToItsSourceLine(needle: String, lines: ClosedRange<Int>) {
    let doc = Rendered("> outer\n> > inner\n>\n> back *out*\n\nAfter.")

    #expect(doc.lines(needle) == lines)
}

private let list = """
    3. third
       continues here
    4. fourth

       second paragraph
       - nested
         - deeper
    - [ ] open task
    """

@Test func listsNumberBulletAndCheckTheirItems() {
    let doc = Rendered(list)

    #expect(
        doc.string == "3.\tthird continues here\n4.\tfourth\nsecond paragraph\n◦\tnested\n▪\tdeeper\n☐\topen task\n")
}

@Test(arguments: [("continues", 2...2), ("second paragraph", 5...5), ("deeper", 7...7)])
func listLineMapsToItsSourceLine(needle: String, lines: ClosedRange<Int>) {
    let doc = Rendered(list)

    #expect(doc.lines(needle) == lines)
}

@Test func nestedListsIndentFurtherEachLevel() throws {
    let doc = Rendered(list)

    let third = try #require(doc.paragraph(of: "third")?.headIndent)
    let nested = try #require(doc.paragraph(of: "nested")?.headIndent)
    let deeper = try #require(doc.paragraph(of: "deeper")?.headIndent)
    #expect(third < nested)
    #expect(nested < deeper)
}

@Test func continuationParagraphLinesUpWithItsItem() {
    let doc = Rendered(list)

    #expect(doc.paragraph(of: "second paragraph")?.headIndent == doc.paragraph(of: "third")?.headIndent)
}

// MARK: - Code

@Test func codeBlocksShowTheirLanguageLabelAndCode() {
    let doc = Rendered("~~~swift\nlet a = 1\n\nlet b = 2\n~~~\n\n    indented\n    more\n")

    #expect(doc.string == "swift\nlet a = 1\n\nlet b = 2\n\nindented\nmore\n\n")
}

@Test(arguments: [("swift", 1...1), ("let a", 2...2), ("let b", 4...4), ("indented", 7...7), ("more", 8...8)])
func codeLineMapsToItsSourceLine(needle: String, lines: ClosedRange<Int>) {
    let doc = Rendered("~~~swift\nlet a = 1\n\nlet b = 2\n~~~\n\n    indented\n    more\n")

    #expect(doc.lines(needle) == lines)
}

@Test func fenceClosesOnlyOnItsOwnCharacter() {
    let doc = Rendered("```\nnot `closed by` ~~~\n")

    #expect(doc.text.contains("not `closed by` ~~~"))
}

@Test(arguments: [("~~~\nfenced\n~~~", "fenced"), ("    indented", "indented")])
func codeRendersMonospacedOnABackground(source: String, code: String) {
    let doc = Rendered(source)

    #expect(doc.traits(of: code).contains(.monoSpace))
    #expect(doc.blocks(of: code).first?.backgroundColor != nil)
}

// MARK: - Tables

private let table = "| Action | How |\n|---|:--:|\n| Open a file | ⌘O |\n| Send | ⌘↩ |\n\nAfter the table."

@Test func tableSyntaxRendersAway() {
    let doc = Rendered(table)

    #expect(!doc.text.contains("|"))
    #expect(!doc.text.contains("---"))
}

@Test(arguments: [("Action", 0, 0), ("How", 0, 1), ("Open a file", 1, 0), ("⌘↩", 2, 1)])
func tableCellSitsInItsRowAndColumn(needle: String, row: Int, column: Int) {
    let doc = Rendered(table)

    #expect(doc.cell(of: needle)?.startingRow == row)
    #expect(doc.cell(of: needle)?.startingColumn == column)
}

@Test func tableCellsShareOneTable() {
    let doc = Rendered(table)

    #expect(doc.cell(of: "Open a file")?.table === doc.cell(of: "Action")?.table)
}

@Test func tableHeaderRowRendersBold() {
    let doc = Rendered(table)

    #expect(doc.traits(of: "Action").contains(.bold))
}

@Test func tableColumnKeepsItsAlignment() {
    let doc = Rendered(table)

    #expect(doc.paragraph(of: "⌘O")?.alignment == .center)
}

@Test func tableColumnsAreSizedToTheirContent() {
    let doc = Rendered(table)

    #expect(doc.cell(of: "Open a file")?.value(for: .width) ?? 0 > doc.cell(of: "⌘O")?.value(for: .width) ?? 0)
}

@Test func tableColumnSharesOneWidth() {
    let doc = Rendered(table)

    #expect(doc.cell(of: "Open a file")?.value(for: .width) == doc.cell(of: "Send")?.value(for: .width))
}

@Test(arguments: [("Open", 3...3), ("Send", 4...4), ("After", 6...6)])
func tableRowMapsToItsSourceLine(needle: String, lines: ClosedRange<Int>) {
    let doc = Rendered(table)

    #expect(doc.lines(needle) == lines)
}

@Test func textAfterATableIsOutsideIt() {
    let doc = Rendered(table)

    #expect(doc.blocks(of: "After").isEmpty)
}

@Test func spannedTableCellKeepsLaterCellsInTheirColumns() {
    let doc = Rendered("| a | b | c | d |\n|---|---|---|---|\n| x ||| y |\n")

    #expect(doc.cell(of: "x")?.columnSpan == 3)
    #expect(doc.cell(of: "y")?.startingColumn == 3)
}

// MARK: - Footnotes and front matter

@Test func footnoteReferencesBecomeSuperscriptLabels() {
    let doc = Rendered("Claim[^1] and more[^note].\n\n[^1]: First source.\n[^note]: Second source.")

    #expect(doc.text.hasPrefix("Claim1 and morenote."))
    #expect(doc.attribute(.baselineOffset, of: "1 and") as? CGFloat ?? 0 > 0)
}

@Test func footnoteDefinitionsListUnderTheirLabels() {
    let doc = Rendered("Claim[^1] and more[^note].\n\n[^1]: First source.\n[^note]: Second source.")

    #expect(doc.text.contains("1 First source.\nnote Second source."))
    #expect(doc.lines("First source") == 3...3)
    #expect(doc.lines("Second source") == 4...4)
}

@Test func footnoteSyntaxInCodeStaysCode() {
    let doc = Rendered("Claim[^1].\n\n[^1]: Source.\n\n`[^1]` stays code.")

    #expect(doc.text.contains("[^1] stays code"))
}

@Test func footnoteDefinitionReferencingAnotherEndsCleanlyAtEndOfFile() {
    let doc = Rendered("A[^1] B[^2]\n\n[^2]: Other.\n[^1]: see [^2]")

    #expect(doc.text.contains("1 see 2"))
}

@Test func frontMatterIsNotListedAsHeadings() {
    let doc = Rendered("---\ntitle: Plan\ntags: [a]\n---\n\n# Real\n")

    #expect(doc.rendered.headings.map(\.title) == ["Real"])
}

@Test func frontMatterShowsAsAMutedBlockWithoutItsFences() {
    let doc = Rendered("---\ntitle: Plan\ntags: [a]\n---\n\n# Real\n")

    #expect(doc.text.hasPrefix("title: Plan\ntags: [a]\n"))
    #expect(!doc.text.contains("---"))
    #expect(doc.attribute(.foregroundColor, of: "title") as? NSColor == .secondaryLabelColor)
}

@Test(arguments: [("title", 2...2), ("tags", 3...3), ("Real", 6...6)])
func frontMatterLineMapsToItsSourceLine(needle: String, lines: ClosedRange<Int>) {
    let doc = Rendered("---\ntitle: Plan\ntags: [a]\n---\n\n# Real\n")

    #expect(doc.lines(needle) == lines)
}

// MARK: - Every character keeps its line

@Test func everyConstructTagsEveryCharacter() {
    let doc = Rendered(
        "---\na: b\n---\n# H\n\n> q\n\n- [x] t\n  1. n\n\n```\nc\n```\n\n"
            + "| a |\n|---|\n| b |\n\n<div>\n\nx[^1]\n\n[^1]: y\n![gone](missing.png)\n")

    #expect(everyCharacterHasALine(doc.rendered.text))
}

@Test func spannedTableCellTagsEveryCharacter() {
    let doc = Rendered("| a | b | c | d |\n|---|---|---|---|\n| x ||| y |\n")

    #expect(everyCharacterHasALine(doc.rendered.text))
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
func extremeAndMalformedMarkdownRendersWithEveryCharacterTagged(source: String) {
    let doc = Rendered(source)

    #expect(everyCharacterHasALine(doc.rendered.text))
}
