import Foundation
import MDReviewCore
import Testing

/// A comment on `quote`, made the way the app makes one: from a selection in the rendered `source`.
private func comment(on quote: String, in source: String, occurrence: Int = 0) throws -> ReviewComment {
    let text = MarkdownRenderer.render(source).text
    var range = (text.string as NSString).range(of: quote)
    for _ in 0..<occurrence {
        let rest = NSMaxRange(range)
        range = (text.string as NSString).range(
            of: quote, range: NSRange(location: rest, length: text.length - rest))
    }
    let lines = try #require(MarkdownRenderer.lineRange(of: range, in: text))
    return ReviewComment(lines: lines, quote: quote, text: "Note", range: range)
}

private func reanchor(_ comment: ReviewComment, to source: String) -> ReviewComment {
    comment.reanchored(in: MarkdownRenderer.render(source).text)
}

@Test func unchangedFileKeepsTheAnchor() throws {
    let source = "# Plan\n\nShip the importer.\n"
    let original = try comment(on: "the importer", in: source)
    #expect(reanchor(original, to: source) == original)
}

@Test func movedTextCarriesTheCommentToItsNewLines() throws {
    let original = try comment(on: "the importer", in: "# Plan\n\nShip the importer.\n")
    let moved = reanchor(original, to: "# Plan\n\nIntro.\n\nMore intro.\n\nShip the importer.\n")
    #expect(moved.lines == 7...7)
    #expect(!moved.isOutdated)
    #expect(moved.text == "Note" && moved.id == original.id)
}

@Test func duplicatedTextPicksTheOccurrenceNearestTheOldPosition() throws {
    let source = "Ship it.\n\nWait.\n\nShip it.\n"
    let second = try comment(on: "Ship it", in: source, occurrence: 1)
    #expect(second.lines == 5...5)
    #expect(reanchor(second, to: "Intro.\n\n" + source).lines == 7...7)
    let first = try comment(on: "Ship it", in: source)
    #expect(reanchor(first, to: "Intro.\n\n" + source).lines == 3...3)
}

@Test func deletedTextMarksTheCommentOutdatedAndKeepsItsOldAnchor() throws {
    let original = try comment(on: "the importer", in: "# Plan\n\nShip the importer.\n")
    let outdated = reanchor(original, to: "# Plan\n\nShip the exporter.\n")
    #expect(outdated.isOutdated)
    #expect(outdated.lines == original.lines && outdated.text == "Note")
    let restored = reanchor(outdated, to: "# Plan\n\nShip the importer.\n")
    #expect(!restored.isOutdated && restored.lines == 3...3)
}

@Test func reformattedTextStillMatchesItsRenderedQuote() throws {
    let original = try comment(on: "the importer", in: "Ship the importer.\n")
    let moved = reanchor(original, to: "# Plan\n\nShip **the importer**.\n")
    #expect(!moved.isOutdated && moved.lines == 3...3)
}

@Test func commentSavedWithoutAnOutdatedFlagStillDecodes() throws {
    let saved =
        #"{"text":"When?","range":[6,8],"id":"178F91EC-977E-4D33-90FC-F3D9DA236313","lines":[3,3],"quote":"Ship it."}"#
    let decoded = try JSONDecoder().decode(ReviewComment.self, from: Data(saved.utf8))
    #expect(decoded.lines == 3...3 && decoded.quote == "Ship it." && decoded.range == NSRange(location: 6, length: 8))
    #expect(!decoded.isOutdated)
}
