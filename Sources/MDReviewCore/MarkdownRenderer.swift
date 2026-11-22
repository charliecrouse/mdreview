import AppKit
import Markdown

/// Renders CommonMark with the GitHub extensions. Every rendered character is tagged with `.sourceLine`,
/// taken from the parser's source ranges, so any rendered selection maps back to exact source lines.
public enum MarkdownRenderer {
    /// `baseURL` is the file's folder: local images load from it and relative links resolve against it.
    public static func render(_ source: String, baseURL: URL? = nil, bodySize: CGFloat = 15) -> RenderedMarkdown {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : String($0)
        }
        let frontMatter = frontMatterEnd(lines).map { end in
            defer { for index in 0...end { lines[index] = "" } }  // blanked, so line numbers stay the file's
            return lines[1..<end]
        }
        var builder = MarkdownBuilder(lines: lines, baseURL: baseURL, bodySize: bodySize)
        if let frontMatter { builder.frontMatter(frontMatter, firstLine: 2) }
        builder.blocks(of: parse(lines), MarkdownBuilder.Context())
        builder.styleFootnotes()
        builder.linkBareURLs()
        return RenderedMarkdown(text: builder.out, headings: builder.headings)
    }

    /// Index of the closing `---` of YAML front matter that opens the file.
    static func frontMatterEnd(_ lines: [String]) -> Int? {
        guard lines.first == "---" else { return nil }
        return lines.indices.dropFirst().first { lines[$0] == "---" || lines[$0] == "..." }
    }

    /// The parser has no footnotes and reads a `[^1]: note` line as a link definition, which renders as
    /// nothing. Escaping its bracket keeps the note as text; code blocks are left alone.
    static func parse(_ lines: [String]) -> Document {
        let options: ParseOptions = [.disableSmartOpts]  // rendered quotes must match the file's own text
        let isDefinition = { (line: String) in line.prefixMatch(of: /\ {0,3}\[\^[^\]\s]+\]:/) != nil }
        guard lines.contains(where: isDefinition) else {
            return Document(parsing: lines.joined(separator: "\n"), options: options)
        }
        let verbatim = verbatimLines(in: Document(parsing: lines.joined(separator: "\n"), options: options))
        let escaped = lines.enumerated().map { index, line in
            isDefinition(line) && !verbatim.contains(index + 1)
                ? line.replacing("[^", with: "\\[^", maxReplacements: 1)
                : line
        }
        return Document(parsing: escaped.joined(separator: "\n"), options: options)
    }

    private static func verbatimLines(in markup: Markup) -> Set<Int> {
        if markup is CodeBlock || markup is HTMLBlock, let range = markup.range {
            return Set(range.lowerBound.line...range.upperBound.line)
        }
        return markup.children.reduce(into: []) { $0.formUnion(verbatimLines(in: $1)) }
    }

    /// Inclusive 1-based source line range covered by a rendered character range.
    public static func lineRange(of range: NSRange, in text: NSAttributedString) -> ClosedRange<Int>? {
        guard range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        var lower = Int.max
        var upper = Int.min
        text.enumerateAttribute(.sourceLine, in: range) { value, _, _ in
            if let line = value as? Int {
                lower = min(lower, line)
                upper = max(upper, line)
            }
        }
        return lower <= upper ? lower...upper : nil
    }

    /// The trimmed rendered text of `range`, or nil when it is only whitespace and so can't be re-found.
    public static func quote(of range: NSRange, in text: NSAttributedString) -> String? {
        guard NSMaxRange(range) <= text.length else { return nil }
        let quote = text.attributedSubstring(from: range).string.trimmingCharacters(in: .whitespacesAndNewlines)
        return quote.isEmpty ? nil : quote
    }

    /// Rendered range of the first characters produced by `line`.
    public static func range(ofLine line: Int, in text: NSAttributedString) -> NSRange? {
        var found: NSRange?
        text.enumerateAttribute(.sourceLine, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            if value as? Int == line {
                found = range
                stop.pointee = true
            }
        }
        return found
    }
}
