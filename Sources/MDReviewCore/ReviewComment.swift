import Foundation

public struct ReviewComment: Identifiable, Hashable, Codable, Sendable {
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
