import Foundation
import MDReviewCore
import Testing

@Test func movedTextCarriesTheCommentToItsNewLines() throws {
    let original = try comment(on: "the importer", in: "# Plan\n\nShip the importer.\n")
    let edited = render("# Plan\n\nIntro.\n\nMore intro.\n\nShip the importer.\n")

    let moved = original.reanchored(from: render("# Plan\n\nShip the importer.\n"), to: edited)

    #expect(moved.lines == 7...7)
    #expect(!moved.isOutdated)
    #expect(moved.id == original.id)
    #expect(moved.text == "Note")
}

@Test func editAboveDuplicatedTextKeepsTheCommentOnTheLastCopy() throws {
    let source = "Ship it.\n\nShip it.\n"
    let last = try comment(on: "Ship it", in: source, lastCopy: true)

    let moved = last.reanchored(from: render(source), to: render("Twenty chars of intr\n\n" + source))

    #expect(!moved.isOutdated)
    #expect(moved.lines == 5...5)
}

@Test func editAboveDuplicatedTextKeepsTheCommentOnTheFirstCopy() throws {
    let source = "Ship it.\n\nShip it.\n"
    let first = try comment(on: "Ship it", in: source)

    let moved = first.reanchored(from: render(source), to: render("Twenty chars of intr\n\n" + source))

    #expect(!moved.isOutdated)
    #expect(moved.lines == 3...3)
}

@Test func rewritingOneCopyOfDuplicatedTextMarksItsCommentOutdatedInPlace() throws {
    let source = "Ship it.\n\nWait.\n\nShip it.\n"
    let last = try comment(on: "Ship it", in: source, lastCopy: true)

    let rewritten = last.reanchored(from: render(source), to: render("Ship it.\n\nWait.\n\nHold it.\n"))

    #expect(rewritten.isOutdated)
    #expect(rewritten.lines == 5...5)
}

@Test func editsAboveAndBelowInOneWriteKeepADuplicatedQuoteBetweenThem() throws {
    let source = "Title\n\nShip it.\n\nShip it.\n\nEnd\n"
    let last = try comment(on: "Ship it", in: source, lastCopy: true)

    let moved = last.reanchored(from: render(source), to: render("Title!\n\nShip it.\n\nShip it.\n\nEnd!\n"))

    #expect(!moved.isOutdated)
    #expect(moved.lines == 5...5)
}

@Test func farApartEditsInOneWriteCarryTheCommentBetweenThem() throws {
    let source = "# Plan\n\nIntro.\n\nShip the importer.\n\nEnd.\n"
    let original = try comment(on: "the importer", in: source)
    let edited = render("# Plan\n\nNew intro.\n\nMore.\n\nShip the importer.\n\nDone.\n")

    let moved = original.reanchored(from: render(source), to: edited)

    #expect(!moved.isOutdated)
    #expect(moved.lines == 7...7)
}

private let repeated = "Please ship it today, and then after that ship it again once every reviewer signs off."

@Test func editOnARepeatedQuotesLineKeepsTheCommentOnTheLastCopy() throws {
    let last = try comment(on: "ship it", in: repeated, lastCopy: true)

    let moved = last.reanchored(from: render(repeated), to: render(repeated + " Then celebrate."))

    #expect(!moved.isOutdated)
    #expect(moved.range == last.range)
}

@Test func editOnARepeatedQuotesLineKeepsTheCommentOnTheFirstCopy() throws {
    let first = try comment(on: "ship it", in: repeated)

    let moved = first.reanchored(from: render(repeated), to: render(repeated + " Then celebrate."))

    #expect(moved.range == first.range)
}

@Test func rewritingTheCommentedCopyOfARepeatedQuoteMarksItOutdatedInsteadOfJumping() throws {
    let last = try comment(on: "ship it", in: repeated, lastCopy: true)
    let edited = render("Please ship it today, and then after that deploy again once every reviewer signs off.")

    let rewritten = last.reanchored(from: render(repeated), to: edited)

    #expect(rewritten.isOutdated)
}

@Test func rewriteWithAnEditAboveMarksTheCommentOutdatedInsteadOfJumping() throws {
    let source = "# Plan\n\nShip it.\n\nWait.\n\nShip it.\n"
    let last = try comment(on: "Ship it", in: source, lastCopy: true)

    let rewritten = last.reanchored(
        from: render(source), to: render("# Plan\n\nContext.\n\nShip it.\n\nWait.\n\nHold it.\n"))

    #expect(rewritten.isOutdated)
}

@Test func deletedTextMarksTheCommentOutdated() throws {
    let original = try comment(on: "the importer", in: "# Plan\n\nShip the importer.\n")

    let outdated = original.reanchored(
        from: render("# Plan\n\nShip the importer.\n"), to: render("# Plan\n\nShip the exporter.\n"))

    #expect(outdated.isOutdated)
}

@Test func outdatedCommentKeepsItsOldLinesAndText() throws {
    let original = try comment(on: "the importer", in: "# Plan\n\nShip the importer.\n")

    let outdated = original.reanchored(
        from: render("# Plan\n\nShip the importer.\n"), to: render("# Plan\n\nShip the exporter.\n"))

    #expect(outdated.lines == 3...3)
    #expect(outdated.range == original.range)
    #expect(outdated.text == "Note")
}

@Test func restoringDeletedTextLeavesTheCommentOutdated() throws {
    let original = try comment(on: "the importer", in: "# Plan\n\nShip the importer.\n")
    let exporter = render("# Plan\n\nShip the exporter.\n")
    let outdated = original.reanchored(from: render("# Plan\n\nShip the importer.\n"), to: exporter)

    let restored = outdated.reanchored(from: exporter, to: render("# Plan\n\nShip the importer.\n"))

    #expect(restored == outdated)
}

@Test func outdatedCommentIsNotRestoredOntoAnAmbiguousMatch() throws {
    let original = try comment(on: "Wait", in: "Ship it.\n\nWait.\n")
    let outdated = original.reanchored(from: render("Ship it.\n\nWait.\n"), to: render("Ship it.\n\nGo.\n"))
    try #require(outdated.isOutdated)

    let ambiguous = outdated.reanchored(from: render("Ship it.\n\nGo.\n"), to: render("Wait.\n\nWait.\n"))

    #expect(ambiguous.isOutdated)
}

@Test func outdatedCommentStaysOutdatedAcrossLaterEdits() throws {
    let source = "Ship it.\n\nWait.\n\nShip it.\n"
    let rewrittenSource = "Ship it.\n\nWait.\n\nHold it.\n"
    let last = try comment(on: "Ship it", in: source, lastCopy: true)
    let rewritten = last.reanchored(from: render(source), to: render(rewrittenSource))
    try #require(rewritten.isOutdated)

    let appended = rewritten.reanchored(from: render(rewrittenSource), to: render(rewrittenSource + "\n\nDone.\n"))

    #expect(appended == rewritten)
}

@Test func reopeningAnUnchangedFileKeepsTheAnchor() throws {
    let source = "# Plan\n\nShip the importer.\n"
    let original = try comment(on: "the importer", in: source)

    let reopened = original.reanchored(in: render(source))

    #expect(reopened == original)
}

@Test func reopeningAfterTheCommentedCopyOfARepeatedQuoteIsRewrittenMarksItOutdated() throws {
    let last = try comment(on: "ship it", in: repeated, lastCopy: true)
    let edited = render("Please ship it today, and then after that deploy again once every reviewer signs off.")

    let reopened = last.reanchored(in: edited)

    #expect(reopened.isOutdated)
}

@Test func reopeningFollowsTheCopyOfARepeatedQuoteWithTheSameContext() throws {
    let last = try comment(on: "ship it", in: repeated, lastCopy: true)
    let edited = render("# Plan\n\nIntro.\n\n" + repeated)

    let reopened = last.reanchored(in: edited)

    #expect(!reopened.isOutdated)
    #expect(reopened.lines == 5...5)
    #expect(
        (edited.string as NSString).substring(from: reopened.range.location)
            == "ship it again once every reviewer signs off.\n")
}

@Test func reopeningAnUnchangedFileKeepsACommentWhoseSelectionIncludedWhitespace() throws {
    let text = render("Ship it.\n\nShip it.\n")
    let last = (text.string as NSString).range(of: "Ship it.", options: .backwards)
    let original = try #require(
        ReviewComment(selection: NSRange(location: last.location - 1, length: last.length + 1), in: text))

    let reopened = original.reanchored(in: text)

    #expect(reopened == original)
}

@Test func reopeningAnUnchangedFileKeepsACommentOnADuplicatedQuote() throws {
    let source = "Ship it.\n\nShip it.\n"
    let last = try comment(on: "Ship it", in: source, lastCopy: true)

    let reopened = last.reanchored(in: render(source))

    #expect(reopened == last)
}

@Test func reopeningAfterADuplicatedQuoteMovedMarksItsCommentOutdated() throws {
    let source = "Ship it.\n\nShip it.\n"
    let last = try comment(on: "Ship it", in: source, lastCopy: true)

    let reopened = last.reanchored(in: render("Intro.\n\n" + source))

    #expect(reopened.isOutdated)
}

@Test func reopeningKeepsAnOutdatedCommentOutdatedEvenWhenItsQuoteIsUnique() throws {
    let source = "Ship it.\n\nWait.\n\nShip it.\n"
    let last = try comment(on: "Ship it", in: source, lastCopy: true)
    let rewritten = last.reanchored(from: render(source), to: render("Ship it.\n\nWait.\n\nHold it.\n"))
    try #require(rewritten.isOutdated)

    let reopened = rewritten.reanchored(in: render("Ship it.\n\nWait.\n\nHold it.\n"))

    #expect(reopened == rewritten)
}

@Test func reopeningReformattedTextStillFindsItsRenderedQuote() throws {
    let original = try comment(on: "the importer", in: "Ship the importer.\n")

    let reopened = original.reanchored(in: render("# Plan\n\nShip **the importer**.\n"))

    #expect(!reopened.isOutdated)
    #expect(reopened.lines == 3...3)
}

@Test func pageCommentIgnoresEditsToTheFile() {
    let page = ReviewComment.page(text: "Overall: too long.")

    let edited = [page].reanchored(from: NSAttributedString(string: "one\ntwo"), to: NSAttributedString(string: "new"))

    #expect(edited == [page])
}

@Test func pageCommentStaysCurrentWhenTheFileIsReopened() {
    let page = ReviewComment.page(text: "Overall: too long.")

    let reopened = page.reanchored(in: NSAttributedString(string: "rewritten entirely"))

    #expect(reopened == page)
}
