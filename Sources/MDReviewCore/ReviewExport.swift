import Foundation

public enum ReviewExport {
    /// The batched review an agent receives: file path, line ranges, quoted text, comment.
    public static func markdown(file: URL, comments: [ReviewComment]) -> String {
        let name = file.lastPathComponent
        var out = """
            # Review of \(name)

            File: `\(file.path)`
            Comments: \(comments.count). Line numbers refer to the file above. Address each comment.

            """
        if comments.contains(where: \.isOutdated) {
            out +=
                "Outdated comments quote text the file no longer contains; their lines are from an earlier version.\n"
        }
        for (index, comment) in comments.sorted(by: { $0.lines.lowerBound < $1.lines.lowerBound }).enumerated() {
            let quote = comment.quote.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(
                separator: "\n")
            let body = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = body.isEmpty ? "_(no comment)_" : body
            let outdated = comment.isOutdated ? " (outdated)" : ""
            out += "\n## \(index + 1). \(name):\(comment.lineLabel)\(outdated)\n\n\(quote)\n\n\(text)\n"
        }
        return out
    }

    /// `notes/plan.md` -> `notes/plan.review.md`
    public static func reviewURL(for file: URL) -> URL {
        file.deletingPathExtension().appendingPathExtension("review.md")
    }
}
