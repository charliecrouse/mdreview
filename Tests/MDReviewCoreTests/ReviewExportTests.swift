import Foundation
import Testing

@testable import MDReviewCore

@Test func reviewExportCarriesPathLinesQuoteAndComment() {
    let file = URL(fileURLWithPath: "/tmp/notes/plan.md")
    let comments = [
        ReviewComment(lines: 9...9, quote: "Backfill", text: "Which workspaces?", range: NSRange()),
        ReviewComment(lines: 3...4, quote: "feature flag\nand enable", text: "  Name the flag.  ", range: NSRange()),
    ]
    let review = ReviewExport.markdown(file: file, comments: comments)

    #expect(review.contains("File: `/tmp/notes/plan.md`"))
    #expect(
        review.contains(
            "## 1. plan.md:3-4 · id \(comments[1].shortID)\n\n> feature flag\n> and enable\n\nName the flag.\n"))
    #expect(review.contains("## 2. plan.md:9 · id \(comments[0].shortID)\n\n> Backfill\n\nWhich workspaces?\n"))
}

@Test func reviewExportLabelsOutdatedComments() {
    var outdated = ReviewComment(lines: 2...2, quote: "Old text", text: "Still relevant?", range: NSRange())
    outdated.isOutdated = true
    let fresh = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [])
    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [outdated])

    #expect(!fresh.contains("Outdated"))
    #expect(review.contains("Outdated comments quote text the file no longer contains"))
    #expect(review.contains("## 1. plan.md:2 · id \(outdated.shortID) (outdated)\n\n> Old text\n\nStill relevant?\n"))
}

@Test func reviewExportShowsTheAgentsEarlierReply() {
    var answered = ReviewComment(lines: 2...2, quote: "Old", text: "Still?", range: NSRange())
    answered.agentReply = "Renamed it"
    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [answered])
    #expect(review.contains("Still?\n\nYour earlier reply: Renamed it\n"))
    #expect(answered.shortID.count == 8 && answered.id.uuidString.lowercased().hasPrefix(answered.shortID))
}

@Test func reviewExportMarksPageCommentsAsWholeFileWithoutLinesOrQuote() {
    let page = ReviewComment.page(text: "Needs a rollback section.")
    let anchored = ReviewComment(lines: 3...3, quote: "Backfill", text: "Which?", range: NSRange())
    let review = ReviewExport.markdown(file: URL(fileURLWithPath: "/tmp/plan.md"), comments: [anchored, page])

    #expect(review.contains("## 1. plan.md (whole file) · id \(page.shortID)\n\nNeeds a rollback section.\n"))
    #expect(review.contains("## 2. plan.md:3 · id \(anchored.shortID)\n\n> Backfill\n\nWhich?\n"))
    #expect(review.contains("A comment marked (whole file) is about the file as a whole"))
}
