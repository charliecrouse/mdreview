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
    /// The quoted text was rewritten, removed or can't be told apart from another copy,
    /// so `lines` and `range` point at an earlier version.
    public var isOutdated = false
    /// Rendered text just before and after the quote, which tells one copy of a repeated quote from another.
    public var prefix = ""
    public var suffix = ""
    /// What the agent answered with `mdreview reply`.
    public var agentReply: String?
    /// The agent proposes the comment is handled; it stays open until the reviewer confirms.
    public var agentSaysDone = false
    /// The reviewer confirmed the comment is handled.
    public var isResolved = false
    /// About the whole file, not a selection: no quote, lines or range, and never outdated.
    public var isPage = false

    private enum CodingKeys: String, CodingKey {
        case id, lines, quote, text, range, isOutdated, prefix, suffix, agentReply, agentSaysDone, isResolved, isPage
    }

    public init(id: UUID = UUID(), lines: ClosedRange<Int>, quote: String, text: String = "", range: NSRange) {
        self.id = id
        self.lines = lines
        self.quote = quote
        self.text = text
        self.range = range
    }

    /// A comment about the whole file. Its zero lines sort it ahead of every anchored comment.
    public static func page(text: String = "") -> ReviewComment {
        var comment = ReviewComment(lines: 0...0, quote: "", text: text, range: NSRange())
        comment.isPage = true
        return comment
    }

    /// A comment on the rendered `selection`, or nil when it covers no source line or only whitespace.
    public init?(selection: NSRange, in text: NSAttributedString) {
        guard let lines = MarkdownRenderer.lineRange(of: selection, in: text),
            let quote = MarkdownRenderer.quote(of: selection, in: text),
            let context = Self.context(of: quote, at: selection, in: text.string as NSString)
        else { return nil }
        self.init(lines: lines, quote: quote, range: selection)
        (prefix, suffix) = context
    }

    /// Records saved before comments could go outdated have no `isOutdated`, and older ones no context;
    /// they load as current, and a repeated quote without context can't be told apart. A range or lines no file
    /// could hold fail, so the store sets the record aside as unreadable.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        lines = try values.decode(ClosedRange<Int>.self, forKey: .lines)
        quote = try values.decode(String.self, forKey: .quote)
        text = try values.decode(String.self, forKey: .text)
        range = try values.decode(NSRange.self, forKey: .range)
        guard range.location >= 0, range.length >= 0, range.location <= Int.max - range.length else {
            throw DecodingError.dataCorruptedError(forKey: .range, in: values, debugDescription: "Impossible range")
        }
        guard lines.lowerBound >= 0, lines.upperBound < Int.max else {
            throw DecodingError.dataCorruptedError(forKey: .lines, in: values, debugDescription: "Impossible lines")
        }
        isOutdated = try values.decodeIfPresent(Bool.self, forKey: .isOutdated) ?? false
        prefix = try values.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        suffix = try values.decodeIfPresent(String.self, forKey: .suffix) ?? ""
        agentReply = try values.decodeIfPresent(String.self, forKey: .agentReply)
        agentSaysDone = try values.decodeIfPresent(Bool.self, forKey: .agentSaysDone) ?? false
        isResolved = try values.decodeIfPresent(Bool.self, forKey: .isResolved) ?? false
        isPage = try values.decodeIfPresent(Bool.self, forKey: .isPage) ?? false
    }

    /// The id an export prints and `mdreview reply` takes: the first 8 hex digits of `id`.
    public var shortID: String { String(id.uuidString.prefix(8)).lowercased() }

    public var lineLabel: String {
        lines.count == 1 ? "\(lines.lowerBound)" : "\(lines.lowerBound)-\(lines.upperBound)"
    }
}
