import Foundation
import MDReviewCore
import Testing

func render(_ source: String) -> NSAttributedString { MarkdownRenderer.render(source).text }

/// A comment saying "Note" on `quote`, made the way the app makes one: from a selection in the rendered `source`.
/// `lastCopy` selects the last copy of a repeated quote instead of the first.
func comment(on quote: String, in source: String, lastCopy: Bool = false) throws -> ReviewComment {
    let text = render(source)
    let range = (text.string as NSString).range(of: quote, options: lastCopy ? .backwards : [])
    let comment = try #require(ReviewComment(selection: range, in: text))
    var list = [comment]
    list.setText("Note", for: comment.id)
    return list[0]
}

private let knownID = UUID(uuidString: "1A2B3C4D-0000-0000-0000-000000000000") ?? UUID()
private let otherID = UUID(uuidString: "5E6F7A8B-0000-0000-0000-000000000000") ?? UUID()

/// A comment with a known id, for replies and edits that name it.
private func known(id: UUID = knownID, text: String = "") -> ReviewComment {
    ReviewComment(id: id, lines: 1...1, quote: "Ship it.", text: text, range: NSRange(location: 0, length: 8))
}

@Test func outdatedFlagSurvivesSavingAndLoading() throws {
    let original = try comment(on: "Ship it", in: "Ship it.\n")
    let outdated = original.reanchored(in: render("Hold it.\n"))

    let decoded = try JSONDecoder().decode(ReviewComment.self, from: JSONEncoder().encode(outdated))

    #expect(decoded.isOutdated)
}

@Test func agentReplySurvivesSavingAndLoading() throws {
    var list = [known()]
    list.apply([ReviewStore.Reply(id: "1a2b3c4d", text: "Done", resolve: true)])

    let decoded = try JSONDecoder().decode(ReviewComment.self, from: JSONEncoder().encode(list[0]))

    #expect(decoded == list[0])
}

@Test func pageCommentSurvivesSavingAndLoading() throws {
    let page = ReviewComment.page(text: "Overall: too long.")

    let decoded = try JSONDecoder().decode(ReviewComment.self, from: JSONEncoder().encode(page))

    #expect(decoded == page)
    #expect(decoded.isPage)
}

@Test func commentSavedBeforeOutdatedFlagsExistedLoadsAsCurrent() throws {
    let saved =
        #"{"text":"When?","range":[6,8],"id":"1A2B3C4D-0000-0000-0000-000000000000","lines":[3,3],"quote":"Ship it."}"#

    let decoded = try JSONDecoder().decode(ReviewComment.self, from: Data(saved.utf8))

    #expect(
        decoded
            == ReviewComment(
                id: knownID, lines: 3...3, quote: "Ship it.", text: "When?", range: NSRange(location: 6, length: 8)))
}

/// A damaged record must be refused as unreadable, not trap when the comment is measured or shown.
@Test(arguments: [
    #""lines":[1,1],"range":[-5,10]"#, #""lines":[1,1],"range":[5,-10]"#,
    #""lines":[1,1],"range":[9223372036854775807,1]"#, #""lines":[0,9223372036854775807],"range":[0,4]"#,
    #""lines":[-1,1],"range":[0,4]"#,
])
func commentWithImpossibleBoundsFailsToLoad(bounds: String) {
    let saved = #"{"id":"1A2B3C4D-0000-0000-0000-000000000000","quote":"Ship","text":"","# + bounds + "}"

    #expect(throws: DecodingError.self) { try JSONDecoder().decode(ReviewComment.self, from: Data(saved.utf8)) }
}

@Test func shortIDIsTheFirstEightHexDigitsOfTheID() {
    let comment = known()

    let short = comment.shortID

    #expect(short == "1a2b3c4d")
}

@Test(arguments: [(3...3, "3"), (3...5, "3-5")])
func lineLabelShowsOneLineOrARange(lines: ClosedRange<Int>, label: String) {
    let comment = ReviewComment(lines: lines, quote: "Ship it.", range: NSRange())

    #expect(comment.lineLabel == label)
}

@Test func settingTextChangesOnlyTheNamedComment() {
    let other = known(id: otherID, text: "Other")
    var list = [known(), other]

    list.setText("Kept", for: knownID)

    #expect(list == [known(text: "Kept"), other])
}

/// A card's field keeps its comment's id while it edits, and may still write after that comment is deleted.
@Test func settingTextOfADeletedCommentChangesNothing() {
    var list = [known(), known(id: otherID, text: "Other")]
    list.delete(knownID)

    list.setText("Half-typed", for: knownID)

    #expect(list == [known(id: otherID, text: "Other")])
}

@Test func resolvingADeletedCommentChangesNothing() {
    var list = [known(), known(id: otherID, text: "Other")]
    list.delete(knownID)

    list.setResolved(true, for: knownID)

    #expect(list == [known(id: otherID, text: "Other")])
}

@Test func resolvingMarksOnlyTheNamedCommentResolved() {
    var list = [known(), known(id: otherID)]

    list.setResolved(true, for: knownID)

    #expect(list.map(\.isResolved) == [true, false])
}

@Test func reopeningWithdrawsTheAgentsClaimThatTheCommentIsDone() {
    var list = [known()]
    list.apply([ReviewStore.Reply(id: "1a2b3c4d", text: "Done", resolve: true)])
    list.setResolved(true, for: knownID)

    list.setResolved(false, for: knownID)

    #expect(!list[0].isResolved)
    #expect(!list[0].agentSaysDone)
}

@Test func replyWithResolveProposesTheCommentIsDoneWithoutResolvingIt() {
    var list = [known()]

    list.apply([ReviewStore.Reply(id: "1a2b3c4d", text: "Done", resolve: true)])

    #expect(list[0].agentReply == "Done")
    #expect(list[0].agentSaysDone)
    #expect(!list[0].isResolved)
}

@Test func replyIDMatchesWhateverItsCase() {
    var list = [known()]

    list.apply([ReviewStore.Reply(id: "1A2B3C4D", text: "Done", resolve: false)])

    #expect(list[0].agentReply == "Done")
}

/// A stale id names no comment; too short a prefix could name any of them.
@Test(arguments: ["zzzzzzzz", "", "1a2"])
func replyNamingNoSingleCommentChangesNothing(id: String) {
    let list = [known(), known(id: otherID)]
    var replied = list

    replied.apply([ReviewStore.Reply(id: id, text: "Stale", resolve: true)])

    #expect(replied == list)
}

@Test func laterReplyWithoutResolveWithdrawsTheProposal() {
    var list = [known()]
    list.apply([ReviewStore.Reply(id: "1a2b3c4d", text: "Done", resolve: true)])

    list.apply([ReviewStore.Reply(id: "1a2b3c4d", text: "Not yet", resolve: false)])

    #expect(list[0].agentReply == "Not yet")
    #expect(!list[0].agentSaysDone)
}
