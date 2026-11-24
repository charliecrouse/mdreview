import Foundation
import MDReviewCore
import Testing

private let planID = UUID(uuidString: "1A2B3C4D-0000-0000-0000-000000000000") ?? UUID()
private let otherID = UUID(uuidString: "5E6F7A8B-0000-0000-0000-000000000000") ?? UUID()

@Test func exportNamesTheReviewedFilesPath() {
    let comment = ReviewComment(lines: 3...3, quote: "Backfill", text: "Which?", range: NSRange())

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/notes/plan.md"), comments: [comment])

    #expect(review.contains("File: `/tmp/notes/plan.md`"))
}

@Test func exportShowsEachCommentWithItsLinesIdQuoteAndText() {
    let comment = ReviewComment(
        id: planID, lines: 9...9, quote: "Backfill", text: "Which workspaces?", range: NSRange())

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [comment])

    #expect(review.contains("## 1. plan.md:9 · id 1a2b3c4d\n\n> Backfill\n\nWhich workspaces?\n"))
}

@Test func exportQuotesEveryLineOfAMultiLineSelection() {
    let comment = ReviewComment(
        id: planID, lines: 3...4, quote: "feature flag\nand enable", text: "Name the flag.", range: NSRange())

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [comment])

    #expect(review.contains("## 1. plan.md:3-4 · id 1a2b3c4d\n\n> feature flag\n> and enable\n\nName the flag.\n"))
}

@Test func exportTrimsWhitespaceAroundTheCommentText() {
    let comment = ReviewComment(lines: 3...3, quote: "Backfill", text: "  Name the flag.  \n", range: NSRange())

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [comment])

    #expect(review.contains("\n\nName the flag.\n"))
}

@Test func exportListsCommentsInLineOrder() {
    let later = ReviewComment(id: planID, lines: 9...9, quote: "Backfill", text: "Which?", range: NSRange())
    let earlier = ReviewComment(id: otherID, lines: 3...3, quote: "flag", text: "Name it.", range: NSRange())

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [later, earlier])

    #expect(review.contains("## 1. plan.md:3 · id 5e6f7a8b"))
    #expect(review.contains("## 2. plan.md:9 · id 1a2b3c4d"))
}

@Test func exportLabelsAnOutdatedComment() {
    let original = ReviewComment(id: planID, lines: 2...2, quote: "Old text", text: "Still relevant?", range: NSRange())
    let outdated = original.reanchored(in: MarkdownRenderer.render("New words").text)

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [outdated])

    #expect(review.contains("Outdated comments quote text the file no longer contains"))
    #expect(review.contains("## 1. plan.md:2 · id 1a2b3c4d (outdated)\n\n> Old text\n\nStill relevant?\n"))
}

@Test func exportOfCurrentCommentsOnlyHasNoOutdatedNote() {
    let comment = ReviewComment(lines: 3...3, quote: "Backfill", text: "Which?", range: NSRange())

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [comment])

    #expect(!review.contains("Outdated"))
}

@Test func exportShowsTheAgentsEarlierReply() {
    var comments = [ReviewComment(id: planID, lines: 2...2, quote: "Old", text: "Still?", range: NSRange())]
    comments.apply([ReviewStore.Reply(id: "1a2b3c4d", text: "Renamed it", resolve: false)])

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: comments)

    #expect(review.contains("Still?\n\nYour earlier reply: Renamed it\n"))
}

@Test func exportMarksAPageCommentAsWholeFileWithoutLinesOrQuote() {
    let page = ReviewComment.page(text: "Needs a rollback section.")

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [page])

    #expect(review.contains(/## 1\. plan\.md \(whole file\) · id [0-9a-f]{8}\n\nNeeds a rollback section\.\n/))
    #expect(review.contains("A comment marked (whole file) is about the file as a whole"))
}

@Test func exportListsPageCommentsBeforeAnchoredOnes() {
    let anchored = ReviewComment(lines: 1...1, quote: "Backfill", text: "Which?", range: NSRange())
    let page = ReviewComment.page(text: "Needs a rollback section.")

    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [anchored, page])

    #expect(review.contains("## 1. plan.md (whole file)"))
    #expect(review.contains("## 2. plan.md:1"))
}
