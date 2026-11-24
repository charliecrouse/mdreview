import Foundation
import Testing

@testable import MDReviewCore

/// A comment on `quote`, made the way the app makes one: from a selection in the rendered `source`.
private func comment(on quote: String, in source: String, occurrence: Int = 0) throws -> ReviewComment {
    let text = MarkdownRenderer.render(source).text
    var range = (text.string as NSString).range(of: quote)
    for _ in 0..<occurrence {
        let rest = NSMaxRange(range)
        range = (text.string as NSString).range(
            of: quote, range: NSRange(location: rest, length: text.length - rest))
    }
    var comment = try #require(ReviewComment(selection: range, in: text))
    comment.text = "Note"
    return comment
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

@Test func editsAboveAndBelowInOneWriteKeepADuplicatedQuoteBetweenThem() throws {
    let source = "Title\n\nShip it.\n\nShip it.\n\nEnd\n"
    let second = try comment(on: "Ship it", in: source, occurrence: 1)
    let moved = second.reanchored(from: render(source), to: render("Title!\n\nShip it.\n\nShip it.\n\nEnd!\n"))
    #expect(!moved.isOutdated && moved.lines == 5...5)
}

@Test func farApartEditsInOneWriteCarryTheCommentBetweenThem() throws {
    let source = "# Plan\n\nIntro.\n\nShip the importer.\n\nEnd.\n"
    let original = try comment(on: "the importer", in: source)
    let edited = "# Plan\n\nNew intro.\n\nMore.\n\nShip the importer.\n\nDone.\n"
    let moved = original.reanchored(from: render(source), to: render(edited))
    #expect(!moved.isOutdated && moved.lines == 7...7)
    #expect(moved.text == "Note" && moved.id == original.id)
}

private let repeated = "Please ship it today, and then after that ship it again once every reviewer signs off."

@Test func editToARepeatedQuotesLineFollowsTheCopyWithTheSameContext() throws {
    let second = try comment(on: "ship it", in: repeated, occurrence: 1)
    let edited = repeated + " Then celebrate."
    let moved = second.reanchored(from: render(repeated), to: render(edited))
    #expect(!moved.isOutdated && moved.range == second.range)
    let first = try comment(on: "ship it", in: repeated)
    #expect(first.reanchored(from: render(repeated), to: render(edited)).range == first.range)
}

@Test func rewritingTheCommentedCopyOfARepeatedQuoteDoesNotJumpToTheOtherCopy() throws {
    let second = try comment(on: "ship it", in: repeated, occurrence: 1)
    let edited = "Please ship it today, and then after that deploy again once every reviewer signs off."
    #expect(second.reanchored(from: render(repeated), to: render(edited)).isOutdated)
}

@Test func reopenAfterTheCommentedCopyOfARepeatedQuoteIsRewrittenMarksItOutdated() throws {
    let second = try comment(on: "ship it", in: repeated, occurrence: 1)
    let edited = "Please ship it today, and then after that deploy again once every reviewer signs off."
    #expect(reanchor(second, to: edited).isOutdated)
}

@Test func reopenFollowsTheCopyOfARepeatedQuoteWithTheSameContext() throws {
    let second = try comment(on: "ship it", in: repeated, occurrence: 1)
    let moved = reanchor(second, to: "# Plan\n\nIntro.\n\n" + repeated)
    #expect(!moved.isOutdated && moved.lines == 5...5)
    #expect(MarkdownRenderer.quote(of: moved.range, in: render("# Plan\n\nIntro.\n\n" + repeated)) == "ship it")
    #expect(moved.range.location == second.range.location + render("# Plan\n\nIntro.\n\n").length)
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
    let original = try #require(ReviewComment(selection: selection, in: text))
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
    #expect(!decoded.isOutdated && decoded.prefix.isEmpty && decoded.suffix.isEmpty)
}

@Test func repliesProposeHandledWithoutResolvingAndStaleIDsAreIgnored() throws {
    var list = [try comment(on: "Ship it", in: "Ship it.\n"), try comment(on: "Ship", in: "Ship it.\n")]
    let target = list[0].shortID
    list.apply([
        .init(id: target.uppercased(), text: "Done", resolve: true),
        .init(id: "zzzzzzzz", text: "Stale", resolve: true),
        .init(id: "", text: "Everything", resolve: true),
    ])
    #expect(list[0].agentReply == "Done" && list[0].agentSaysDone && !list[0].isResolved)
    #expect(list[1].agentReply == nil)
    list.apply([.init(id: target, text: "Not yet", resolve: false)])
    #expect(list[0].agentReply == "Not yet" && !list[0].agentSaysDone)

    let decoded = try JSONDecoder().decode(ReviewComment.self, from: JSONEncoder().encode(list[0]))
    #expect(decoded == list[0])
}

@Test func pageCommentsSurviveReanchoringAndReload() throws {
    let page = ReviewComment.page(text: "Overall: too long.")
    let old = NSAttributedString(string: "one\ntwo")
    let new = NSAttributedString(string: "rewritten entirely")

    #expect([page].reanchored(from: old, to: new) == [page])
    #expect(page.reanchored(in: new) == page)
    #expect(!page.reanchored(in: new).isOutdated)
    let decoded = try JSONDecoder().decode(ReviewComment.self, from: JSONEncoder().encode(page))
    #expect(decoded.isPage && decoded == page)
}

/// A damaged record must be refused as unreadable, not trap when the comment is measured or shown.
@Test(arguments: [
    #""lines":[1,1],"range":[-5,10]"#, #""lines":[1,1],"range":[5,-10]"#,
    #""lines":[1,1],"range":[9223372036854775807,1]"#, #""lines":[0,9223372036854775807],"range":[0,4]"#,
    #""lines":[-1,1],"range":[0,4]"#,
])
func commentWithImpossibleBoundsFailsToDecode(bounds: String) {
    let saved =
        #"{"id":"178F91EC-977E-4D33-90FC-F3D9DA236313","quote":"Ship","text":"","isOutdated":true,"#
        + bounds + "}"
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(ReviewComment.self, from: Data(saved.utf8)) }
}

/// A card's field keeps the comment's id while it edits, and may still write after its comment is deleted.
@Test(arguments: ["", "Half-typed"])
func deletingACommentWhileItIsEditedLeavesTheOthersIntact(typed: String) throws {
    let source = "Ship it.\n\nHold it.\n"
    let others = [try comment(on: "Ship", in: source), try comment(on: "Hold", in: source)]
    var editing = ReviewComment.page()
    editing.text = typed
    var list = [editing] + others

    list.delete(editing.id)
    list.setText(typed + " more", for: editing.id)
    list.setResolved(true, for: editing.id)
    #expect(list == others)

    list.setText("Kept", for: others[1].id)
    list.setResolved(true, for: others[0].id)
    #expect(list.map(\.text) == ["Note", "Kept"] && list.map(\.isResolved) == [true, false])
}
