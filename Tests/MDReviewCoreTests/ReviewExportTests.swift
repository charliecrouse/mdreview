import Foundation
import MDReviewCore
import Testing

@Test func reviewExportCarriesPathLinesQuoteAndComment() {
    let file = URL(fileURLWithPath: "/tmp/notes/plan.md")
    let comments = [
        ReviewComment(lines: 9...9, quote: "Backfill", text: "Which workspaces?", range: NSRange()),
        ReviewComment(lines: 3...4, quote: "feature flag\nand enable", text: "  Name the flag.  ", range: NSRange()),
    ]
    let review = ReviewExport.markdown(file: file, comments: comments)

    #expect(review.contains("File: `/tmp/notes/plan.md`"))
    #expect(review.contains("## 1. plan.md:3-4\n\n> feature flag\n> and enable\n\nName the flag.\n"))
    #expect(review.contains("## 2. plan.md:9\n\n> Backfill\n\nWhich workspaces?\n"))
}
