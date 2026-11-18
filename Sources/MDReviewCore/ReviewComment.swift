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
    /// The quoted text is no longer in the file, so `lines` and `range` point at an earlier version.
    public var isOutdated = false

    private enum CodingKeys: String, CodingKey { case id, lines, quote, text, range, isOutdated }

    public init(id: UUID = UUID(), lines: ClosedRange<Int>, quote: String, text: String = "", range: NSRange) {
        self.id = id
        self.lines = lines
        self.quote = quote
        self.text = text
        self.range = range
    }

    /// Records saved before comments could go outdated have no `isOutdated`; they load as current.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        lines = try values.decode(ClosedRange<Int>.self, forKey: .lines)
        quote = try values.decode(String.self, forKey: .quote)
        text = try values.decode(String.self, forKey: .text)
        range = try values.decode(NSRange.self, forKey: .range)
        isOutdated = try values.decodeIfPresent(Bool.self, forKey: .isOutdated) ?? false
    }

    public var lineLabel: String {
        lines.count == 1 ? "\(lines.lowerBound)" : "\(lines.lowerBound)-\(lines.upperBound)"
    }
}
