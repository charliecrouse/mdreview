import AppKit

extension ReviewComment {
    /// The comment moved to the occurrence of its quote in a re-rendered `text` nearest its old position,
    /// or marked outdated when the quote is gone. An outdated comment whose text comes back is restored.
    public func reanchored(in text: NSAttributedString) -> ReviewComment {
        let string = text.string as NSString
        var nearest: NSRange?
        var search = NSRange(location: 0, length: string.length)
        while true {
            let match = string.range(of: quote, options: .literal, range: search)
            if match.location == NSNotFound { break }
            if nearest.map({ distance(to: match) < distance(to: $0) }) ?? true { nearest = match }
            search = NSRange(location: match.location + 1, length: string.length - match.location - 1)
        }
        var moved = self
        if let nearest, let lines = MarkdownRenderer.lineRange(of: nearest, in: text) {
            moved.range = nearest
            moved.lines = lines
            moved.isOutdated = false
        } else {
            moved.isOutdated = true
        }
        return moved
    }

    private func distance(to match: NSRange) -> Int { abs(match.location - range.location) }
}
