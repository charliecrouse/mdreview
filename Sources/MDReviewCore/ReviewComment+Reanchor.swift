import AppKit

extension ReviewComment {
    /// The comment re-anchored in `text` with no earlier version to compare against, as when a file is reopened.
    /// It stays put while its quote is still at its range, moves only when the quote occurs exactly once,
    /// and is otherwise marked outdated rather than guessing between occurrences.
    public func reanchored(in text: NSAttributedString) -> ReviewComment {
        let string = text.string as NSString
        if !isOutdated, NSMaxRange(range) <= string.length, string.substring(with: range) == quote {
            return anchored(at: range, in: text)
        }
        let matches = occurrences(in: string, within: NSRange(location: 0, length: string.length))
        return matches.count == 1 ? anchored(at: matches[0], in: text) : outdated()
    }

    /// The comment carried from `old` to `new` through the one span that changed between them:
    /// it keeps its offset before the change, shifts with the text after it, and is searched for
    /// only within the change when it overlaps it, so it can't jump to another copy of its quote.
    public func reanchored(from old: NSAttributedString, to new: NSAttributedString) -> ReviewComment {
        if isOutdated { return reanchored(in: new) }
        let oldString = old.string as NSString
        let newString = new.string as NSString
        let shortest = min(oldString.length, newString.length)
        var prefix = 0
        while prefix < shortest, oldString.character(at: prefix) == newString.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < shortest - prefix,
            oldString.character(at: oldString.length - 1 - suffix)
                == newString.character(at: newString.length - 1 - suffix)
        {
            suffix += 1
        }
        let delta = newString.length - oldString.length
        if NSMaxRange(range) <= prefix { return anchored(at: range, in: new) }
        if range.location >= oldString.length - suffix {
            return anchored(at: NSRange(location: range.location + delta, length: range.length), in: new)
        }
        let start = min(range.location, prefix)
        let end = max(NSMaxRange(range) + delta, newString.length - suffix)
        let window = NSRange(location: start, length: min(end, newString.length) - start)
        return occurrences(in: newString, within: window).first.map { anchored(at: $0, in: new) } ?? outdated()
    }

    private func occurrences(in string: NSString, within window: NSRange) -> [NSRange] {
        var matches: [NSRange] = []
        var search = window
        while true {
            let match = string.range(of: quote, options: .literal, range: search)
            if match.location == NSNotFound { return matches }
            matches.append(match)
            search = NSRange(location: match.location + 1, length: NSMaxRange(window) - match.location - 1)
        }
    }

    private func anchored(at match: NSRange, in text: NSAttributedString) -> ReviewComment {
        guard let lines = MarkdownRenderer.lineRange(of: match, in: text) else { return outdated() }
        var moved = self
        moved.range = match
        moved.lines = lines
        moved.isOutdated = false
        return moved
    }

    private func outdated() -> ReviewComment {
        var moved = self
        moved.isOutdated = true
        return moved
    }
}
