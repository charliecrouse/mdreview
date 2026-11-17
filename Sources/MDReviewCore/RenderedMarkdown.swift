import AppKit

extension NSAttributedString.Key {
    /// 1-based source line that produced a rendered character. Every rendered character carries one.
    public static let sourceLine = NSAttributedString.Key("mdreview.sourceLine")
}

public struct Heading: Identifiable, Hashable, Sendable {
    public let line: Int
    public let level: Int
    public let title: String
    public var id: Int { line }
}

public struct RenderedMarkdown {
    public let text: NSAttributedString
    public let headings: [Heading]

    public init(text: NSAttributedString = NSAttributedString(), headings: [Heading] = []) {
        self.text = text
        self.headings = headings
    }
}
