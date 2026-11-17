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
        for (i, c) in comments.sorted(by: { $0.lines.lowerBound < $1.lines.lowerBound }).enumerated() {
            let quote = c.quote.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(
                separator: "\n")
            let body = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            out += "\n## \(i + 1). \(name):\(c.lineLabel)\n\n\(quote)\n\n\(body.isEmpty ? "_(no comment)_" : body)\n"
        }
        return out
    }

    /// `notes/plan.md` -> `notes/plan.review.md`
    public static func reviewURL(for file: URL) -> URL {
        file.deletingPathExtension().appendingPathExtension("review.md")
    }
}
