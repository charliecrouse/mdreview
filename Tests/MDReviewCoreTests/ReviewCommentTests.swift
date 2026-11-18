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

private func render(_ source: String) -> NSAttributedString { MarkdownRenderer.render(source).text }

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

@Test func liveEditAboveDuplicatedTextKeepsTheCommentOnItsOccurrence() throws {
    let source = "Ship it.\n\nShip it.\n"
    let second = try comment(on: "Ship it", in: source, occurrence: 1)
    #expect(second.lines == 3...3)
    let edited = "Twenty chars of intr\n\n" + source
    let moved = second.reanchored(from: render(source), to: render(edited))
    #expect(!moved.isOutdated && moved.lines == 5...5)
    let first = try comment(on: "Ship it", in: source)
    #expect(first.reanchored(from: render(source), to: render(edited)).lines == 3...3)
}

@Test func liveRewriteOfDuplicatedTextMarksOutdatedInsteadOfJumping() throws {
    let source = "Ship it.\n\nWait.\n\nShip it.\n"
    let second = try comment(on: "Ship it", in: source, occurrence: 1)
    let rewritten = second.reanchored(from: render(source), to: render("Ship it.\n\nWait.\n\nHold it.\n"))
    #expect(rewritten.isOutdated && rewritten.lines == 5...5)
}

@Test func editsAboveAndBelowInOneWriteOutdateADuplicatedQuoteBetweenThem() throws {
    let source = "Title\n\nShip it.\n\nShip it.\n\nEnd\n"
    let second = try comment(on: "Ship it", in: source, occurrence: 1)
    let moved = second.reanchored(from: render(source), to: render("Title!\n\nShip it.\n\nShip it.\n\nEnd!\n"))
    #expect(moved.isOutdated && moved.range == second.range)
}

@Test func rewriteWithAnEditAboveDoesNotJumpToTheOtherCopy() throws {
    let source = "# Plan\n\nShip it.\n\nWait.\n\nShip it.\n"
    let second = try comment(on: "Ship it", in: source, occurrence: 1)
    let edited = "# Plan\n\nContext.\n\nShip it.\n\nWait.\n\nHold it.\n"
    #expect(second.reanchored(from: render(source), to: render(edited)).isOutdated)
}

@Test func reopeningAnUnchangedFileKeepsACommentWhoseSelectionIncludedWhitespace() throws {
    let source = "Ship it.\n\nShip it.\n"
    let text = render(source)
    let second = (text.string as NSString).range(of: "Ship it.", options: .backwards)
    let selection = NSRange(location: second.location - 1, length: second.length + 1)
    let lines = try #require(MarkdownRenderer.lineRange(of: selection, in: text))
    let quote = try #require(MarkdownRenderer.quote(of: selection, in: text))
    let original = ReviewComment(lines: lines, quote: quote, range: selection)
    #expect(original.reanchored(in: text) == original)
}

@Test func reopenWithDuplicatedQuoteKeepsAnUnmovedCommentAndOutdatesAMovedOne() throws {
    let source = "Ship it.\n\nShip it.\n"
    let second = try comment(on: "Ship it", in: source, occurrence: 1)
    #expect(reanchor(second, to: source) == second)
    #expect(reanchor(second, to: "Intro.\n\n" + source).isOutdated)
}

@Test func outdatedCommentIsNotRestoredOntoAnAmbiguousMatch() throws {
    let source = "Ship it.\n\nWait.\n"
    let original = try comment(on: "Wait", in: source)
    let outdated = original.reanchored(from: render(source), to: render("Ship it.\n\nGo.\n"))
    #expect(outdated.isOutdated)
    let ambiguous = outdated.reanchored(from: render("Ship it.\n\nGo.\n"), to: render("Wait.\n\nWait.\n"))
    #expect(ambiguous.isOutdated)
}

@Test func deletedTextMarksTheCommentOutdatedAndKeepsItsOldAnchor() throws {
    let original = try comment(on: "the importer", in: "# Plan\n\nShip the importer.\n")
    let exporter = render("# Plan\n\nShip the exporter.\n")
    let outdated = original.reanchored(from: render("# Plan\n\nShip the importer.\n"), to: exporter)
    #expect(outdated.isOutdated)
    #expect(outdated.lines == original.lines && outdated.text == "Note")
    #expect(outdated.reanchored(from: exporter, to: render("# Plan\n\nShip the importer.\n")) == outdated)
}

@Test func outdatedCommentStaysOutdatedAcrossLaterEdits() throws {
    let source = "Ship it.\n\nWait.\n\nShip it.\n"
    let second = try comment(on: "Ship it", in: source, occurrence: 1)
    let rewrittenSource = "Ship it.\n\nWait.\n\nHold it.\n"
    let rewritten = second.reanchored(from: render(source), to: render(rewrittenSource))
    #expect(rewritten.isOutdated)
    let appended = rewritten.reanchored(from: render(rewrittenSource), to: render(rewrittenSource + "\n\nDone.\n"))
    #expect(appended == rewritten && appended.range == second.range && appended.lines == second.lines)
}

@Test func reformattedTextStillMatchesItsRenderedQuote() throws {
    let original = try comment(on: "the importer", in: "Ship the importer.\n")
    let moved = reanchor(original, to: "# Plan\n\nShip **the importer**.\n")
    #expect(!moved.isOutdated && moved.lines == 3...3)
}

@Test func reopeningKeepsAnOutdatedCommentOutdatedEvenWhenItsQuoteIsUnique() throws {
    let source = "Ship it.\n\nWait.\n\nShip it.\n"
    let second = try comment(on: "Ship it", in: source, occurrence: 1)
    let rewritten = second.reanchored(from: render(source), to: render("Ship it.\n\nWait.\n\nHold it.\n"))
    #expect(rewritten.isOutdated)
    #expect(reanchor(rewritten, to: "Ship it.\n\nWait.\n\nHold it.\n") == rewritten)
}

@Test func outdatedFlagSurvivesSavingAndLoading() throws {
    var outdated = try comment(on: "Ship it", in: "Ship it.\n")
    outdated.isOutdated = true
    let decoded = try JSONDecoder().decode(ReviewComment.self, from: JSONEncoder().encode(outdated))
    #expect(decoded == outdated && decoded.isOutdated)
}

@Test func commentSavedWithoutAnOutdatedFlagStillDecodes() throws {
    let saved =
        #"{"text":"When?","range":[6,8],"id":"178F91EC-977E-4D33-90FC-F3D9DA236313","lines":[3,3],"quote":"Ship it."}"#
    let decoded = try JSONDecoder().decode(ReviewComment.self, from: Data(saved.utf8))
    #expect(decoded.lines == 3...3 && decoded.quote == "Ship it." && decoded.range == NSRange(location: 6, length: 8))
    #expect(!decoded.isOutdated)
}
