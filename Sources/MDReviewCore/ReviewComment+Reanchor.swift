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
        let matches = Self.occurrences(of: quote, in: string)
        return matches.count == 1 ? anchored(at: matches[0], in: text) : outdated()
    }

    /// The comment carried from `old` to `new` through the one span that changed between them:
    /// it keeps its offset before the change and shifts with the text after it. When it overlaps the change,
    /// it follows the shortest text before or after it that was unique in `old`, and is outdated unless
    /// that text occurs exactly once in `new`, so it can't jump to another copy of its quote.
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
        for location in [range.location, range.location + delta] {
            let candidate = NSRange(location: location, length: range.length)
            if NSMaxRange(candidate) <= newString.length, newString.substring(with: candidate) == quote {
                return anchored(at: candidate, in: new)
            }
        }
        for (before, after) in [(1, 0), (0, 1)] {
            var context = range
            while Self.occurrences(of: oldString.substring(with: context), in: oldString).count > 1,
                context.location >= before, NSMaxRange(context) + after <= oldString.length
            {
                context = NSRange(location: context.location - before, length: context.length + before + after)
            }
            let text = oldString.substring(with: context)
            let matches = Self.occurrences(of: text, in: newString)
            if matches.count == 1, Self.occurrences(of: text, in: oldString).count == 1 {
                let location = matches[0].location + range.location - context.location
                return anchored(at: NSRange(location: location, length: range.length), in: new)
            }
        }
        return outdated()
    }

    private static func occurrences(of target: String, in string: NSString) -> [NSRange] {
        var matches: [NSRange] = []
        var search = NSRange(location: 0, length: string.length)
        while true {
            let match = string.range(of: target, options: .literal, range: search)
            if match.location == NSNotFound { return matches }
            matches.append(match)
            search = NSRange(location: match.location + 1, length: string.length - match.location - 1)
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
