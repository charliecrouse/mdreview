import AppKit

extension ReviewComment {
    /// Characters of rendered text kept on each side of the quote, as in a W3C TextQuoteSelector.
    static let contextLength = 30

    /// The comment re-anchored in `text` with no earlier version to compare against, as when a file is reopened.
    /// Stays put while the quote is still at `range`, moves only when one copy of the quote is left once its
    /// surrounding text is compared and that copy keeps at least one side of it, and is otherwise marked outdated
    /// rather than guessing between copies.
    /// An outdated comment stays outdated.
    public func reanchored(in text: NSAttributedString) -> ReviewComment {
        if isOutdated || isPage { return self }
        let string = text.string as NSString
        if MarkdownRenderer.quote(of: range, in: text) == quote {
            return anchored(at: range, in: text)
        }
        let matches = candidates(in: string, within: NSRange(location: 0, length: string.length))
        guard matches.count == 1, sharesContext(at: matches[0], in: string) else { return outdated() }
        return anchored(at: matches[0], in: text)
    }

    /// Whether a lone copy keeps at least one side of the saved surrounding text. A comment saved without any
    /// context has nothing to compare and is accepted.
    private func sharesContext(at match: NSRange, in string: NSString) -> Bool {
        if prefix.isEmpty && suffix.isEmpty { return true }
        guard let context = Self.context(of: quote, at: match, in: string) else { return false }
        return context.prefix == prefix || context.suffix == suffix
    }

    /// The comment carried from `old` to `new` through a line-by-line diff: it shifts with its lines while they
    /// are unchanged. When the edit touches its lines, it moves only if one copy of its quote is left in the
    /// changed lines both before and after the edit, once surrounding text is compared, and is otherwise marked
    /// outdated rather than guessing between copies. An outdated comment stays outdated.
    public func reanchored(from old: NSAttributedString, to new: NSAttributedString) -> ReviewComment {
        [self].reanchored(from: old, to: new)[0]
    }

    /// The line-by-line diff between two versions of the text, computed once and shared by every comment.
    fileprivate struct LineDiff {
        let new: NSAttributedString
        let oldString: NSString
        let newString: NSString
        let oldLines: [NSRange]
        let newLines: [NSRange]
        let kept: [Int?]

        init(from old: NSAttributedString, to new: NSAttributedString) {
            self.new = new
            oldString = old.string as NSString
            newString = new.string as NSString
            oldLines = ReviewComment.lines(of: oldString)
            newLines = ReviewComment.lines(of: newString)
            kept = ReviewComment.unchangedLines(
                from: oldLines.map(oldString.substring(with:)), to: newLines.map(newString.substring(with:)))
        }
    }

    fileprivate func reanchored(through diff: LineDiff) -> ReviewComment {
        if isOutdated || isPage { return self }
        let (new, oldString, newString) = (diff.new, diff.oldString, diff.newString)
        let (oldLines, newLines, kept) = (diff.oldLines, diff.newLines, diff.kept)
        let first = oldLines.lastIndex { $0.location <= range.location } ?? 0
        let last = oldLines.lastIndex { $0.location <= max(range.location, NSMaxRange(range) - 1) } ?? first
        if let start = kept[first], (first...last).allSatisfy({ kept[$0] == start + $0 - first }) {
            let offset = newLines[start].location - oldLines[first].location
            return anchored(at: NSRange(location: range.location + offset, length: range.length), in: new)
        }
        let above = kept[..<first].lastIndex { $0 != nil }
        let below = kept[(last + 1)...].firstIndex { $0 != nil }
        let oldHunk = Self.span((above.map { $0 + 1 } ?? 0)..<(below ?? oldLines.count), of: oldLines)
        let newHunk = Self.span(
            (above.flatMap { kept[$0] }.map { $0 + 1 } ?? 0)..<(below.flatMap { kept[$0] } ?? newLines.count),
            of: newLines)
        let before = candidates(in: oldString, within: oldHunk)
        let wasRepeated = Self.occurrences(of: quote, in: oldString, within: oldHunk).count > 1
        let after = candidates(in: newString, within: newHunk, comparingContext: wasRepeated)
        return before.count == 1 && after.count == 1 ? anchored(at: after[0], in: new) : outdated()
    }

    /// The text around the first copy of `quote` inside `match`, or nil when `match` doesn't hold it.
    static func context(of quote: String, at match: NSRange, in string: NSString) -> (prefix: String, suffix: String)? {
        guard NSMaxRange(match) <= string.length else { return nil }
        let found = string.range(of: quote, options: .literal, range: match)
        guard found.location != NSNotFound else { return nil }
        let start = max(0, found.location - contextLength)
        let end = min(string.length, NSMaxRange(found) + contextLength)
        let prefix = NSRange(location: start, length: found.location - start)
        let suffix = NSRange(location: NSMaxRange(found), length: end - NSMaxRange(found))
        return (
            string.substring(with: string.rangeOfComposedCharacterSequences(for: prefix)),
            string.substring(with: string.rangeOfComposedCharacterSequences(for: suffix))
        )
    }

    /// The copies of the quote in `window`, narrowed to those with the saved surrounding text when there are several
    /// or when `comparingContext` asks for it even for a lone copy.
    private func candidates(
        in string: NSString, within window: NSRange, comparingContext: Bool = false
    ) -> [NSRange] {
        let matches = Self.occurrences(of: quote, in: string, within: window)
        guard comparingContext || matches.count > 1 else { return matches }
        return matches.filter { match in
            Self.context(of: quote, at: match, in: string).map { $0 == (prefix, suffix) } ?? false
        }
    }

    private static func occurrences(of target: String, in string: NSString, within window: NSRange) -> [NSRange] {
        var matches: [NSRange] = []
        var search = window
        while true {
            let match = string.range(of: target, options: .literal, range: search)
            if match.location == NSNotFound { return matches }
            matches.append(match)
            search = NSRange(location: match.location + 1, length: NSMaxRange(window) - match.location - 1)
        }
    }

    /// Each line's range in `string`, without its line break.
    private static func lines(of string: NSString) -> [NSRange] {
        var lines: [NSRange] = []
        var start = 0
        while true {
            let rest = NSRange(location: start, length: string.length - start)
            let lineBreak = string.range(of: "\n", options: .literal, range: rest)
            if lineBreak.location == NSNotFound {
                lines.append(rest)
                return lines
            }
            lines.append(NSRange(location: start, length: lineBreak.location - start))
            start = NSMaxRange(lineBreak)
        }
    }

    /// For each old line, the index of the same line in the new text, or nil when the edit removed or rewrote it.
    private static func unchangedLines(from old: [String], to new: [String]) -> [Int?] {
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var next = 0
        return old.indices.map { line in
            if removed.contains(line) { return nil }
            while inserted.contains(next) { next += 1 }
            defer { next += 1 }
            return next
        }
    }

    private static func span(_ lines: Range<Int>, of ranges: [NSRange]) -> NSRange {
        guard let first = lines.first, let last = lines.last else { return NSRange() }
        return NSRange(location: ranges[first].location, length: NSMaxRange(ranges[last]) - ranges[first].location)
    }

    private func anchored(at match: NSRange, in text: NSAttributedString) -> ReviewComment {
        guard let lines = MarkdownRenderer.lineRange(of: match, in: text),
            let context = Self.context(of: quote, at: match, in: text.string as NSString)
        else { return outdated() }
        var moved = self
        moved.range = match
        moved.lines = lines
        moved.isOutdated = false
        (moved.prefix, moved.suffix) = context
        return moved
    }

    private func outdated() -> ReviewComment {
        var moved = self
        moved.isOutdated = true
        return moved
    }
}

extension [ReviewComment] {
    /// Every comment carried from `old` to `new`, diffing the two texts once for all of them.
    public func reanchored(from old: NSAttributedString, to new: NSAttributedString) -> [ReviewComment] {
        let diff = ReviewComment.LineDiff(from: old, to: new)
        return map { $0.reanchored(through: diff) }
    }
}
