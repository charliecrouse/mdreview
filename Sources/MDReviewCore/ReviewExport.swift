import Foundation

public enum ReviewExport {
    /// The batched review an agent receives: file path, line ranges, quoted text, comment.
    public static func markdown(file: URL, comments: [ReviewComment]) -> String {
        let name = file.lastPathComponent
        var out = """
            # Review of \(name)

            File: `\(file.path)`
            Comments: \(comments.count). Line numbers refer to the file above. Address each comment, then answer it with
            `mdreview reply <file> <id> "<what you did>" --resolve`.

            """
        if comments.contains(where: \.isPage) {
            out += "A comment marked (whole file) is about the file as a whole; it has no line range or quote.\n"
        }
        if comments.contains(where: \.isOutdated) {
            out +=
                "Outdated comments quote text the file no longer contains; their lines are from an earlier version.\n"
        }
        for (index, comment) in comments.sorted(by: { $0.lines.lowerBound < $1.lines.lowerBound }).enumerated() {
            let quote =
                comment.isPage
                ? ""
                : comment.quote.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(
                    separator: "\n") + "\n\n"
            let place = comment.isPage ? "\(name) (whole file)" : "\(name):\(comment.lineLabel)"
            let body = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = body.isEmpty ? "_(no comment)_" : body
            let outdated = comment.isOutdated ? " (outdated)" : ""
            let reply = comment.agentReply.map { "\nYour earlier reply: \($0)\n" } ?? ""
            out +=
                "\n## \(index + 1). \(place) · id \(comment.shortID)\(outdated)"
                + "\n\n\(quote)\(text)\n\(reply)"
        }
        return out
    }
}
