import Foundation

public struct ReviewComment: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Inclusive 1-based source lines the comment is anchored to.
    public var lines: ClosedRange<Int>
    /// The rendered text the reviewer selected.
    public var quote: String
    public var text: String
    /// Rendered character range, used to highlight the anchor while the file is open.
    public var range: NSRange

    public init(id: UUID = UUID(), lines: ClosedRange<Int>, quote: String, text: String = "", range: NSRange) {
        self.id = id
        self.lines = lines
        self.quote = quote
        self.text = text
        self.range = range
    }

    public var lineLabel: String {
        lines.count == 1 ? "\(lines.lowerBound)" : "\(lines.lowerBound)-\(lines.upperBound)"
    }
}

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
