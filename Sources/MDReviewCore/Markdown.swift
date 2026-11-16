import AppKit

public extension NSAttributedString.Key {
    /// 1-based source line that produced a rendered character. Every rendered character carries one.
    static let sourceLine = NSAttributedString.Key("mdreview.sourceLine")
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

/// Line-oriented Markdown renderer. Each source line is rendered on its own and tagged with
/// `.sourceLine`, so any rendered selection maps back to exact source lines.
/// ponytail: block structure is parsed line by line (headings, lists, quotes, fences, tables, rules);
/// inline spans that cross a soft line break render literally. Swap in swift-markdown if that matters.
public enum MarkdownRenderer {
    public static func render(_ source: String, bodySize: CGFloat = 15) -> RenderedMarkdown {
        let out = NSMutableAttributedString()
        var headings: [Heading] = []
        var inFence = false
        var openParagraph = false
        var gap = false // a blank line precedes the next block
        var paragraphStyle = NSMutableParagraphStyle()

        let body = NSFont.systemFont(ofSize: bodySize)
        let mono = NSFont.monospacedSystemFont(ofSize: bodySize - 2, weight: .regular)

        func style(indent: CGFloat = 0, hang: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 8) -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.3
            p.firstLineHeadIndent = indent
            p.headIndent = indent + hang
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            return p
        }

        func closeParagraph(line: Int) {
            guard openParagraph else { return }
            out.append(NSAttributedString(string: "\n", attributes: [.sourceLine: line, .paragraphStyle: paragraphStyle]))
            openParagraph = false
        }

        func block(_ content: NSAttributedString, line: Int, paragraph: NSMutableParagraphStyle) {
            if gap { paragraph.paragraphSpacingBefore = max(paragraph.paragraphSpacingBefore, 10) }
            gap = false
            let piece = NSMutableAttributedString(attributedString: content)
            piece.append(NSAttributedString(string: "\n"))
            let all = NSRange(location: 0, length: piece.length)
            piece.addAttribute(.paragraphStyle, value: paragraph, range: all)
            piece.addAttribute(.sourceLine, value: line, range: all)
            out.append(piece)
        }

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let n = index + 1
            var line = String(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                closeParagraph(line: n - 1)
                inFence.toggle()
                continue
            }
            if inFence {
                block(NSAttributedString(string: line.isEmpty ? " " : line, attributes: [
                    .font: mono, .foregroundColor: NSColor.textColor, .backgroundColor: codeBackground,
                ]), line: n, paragraph: style(indent: 12, after: 0))
                continue
            }
            if trimmed.isEmpty {
                closeParagraph(line: n - 1)
                gap = true
                continue
            }

            if let m = trimmed.wholeMatch(of: /(#{1,6})\s+(.*?)\s*#*/) {
                closeParagraph(line: n - 1)
                let level = m.1.count
                let title = String(m.2)
                let sizes: [CGFloat] = [28, 22, 18, 16, 15, 15]
                let size = sizes[level - 1] * bodySize / 15
                let font = NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
                headings.append(Heading(line: n, level: level, title: title))
                block(inline(title, font: font, line: n), line: n,
                      paragraph: style(before: level <= 2 ? 18 : 12, after: 6))
            } else if trimmed.wholeMatch(of: /([-*_])(\s*\1){2,}/) != nil {
                closeParagraph(line: n - 1)
                let p = style(after: 10)
                p.alignment = .center
                block(NSAttributedString(string: "· · ·", attributes: [.font: body, .foregroundColor: NSColor.tertiaryLabelColor]),
                      line: n, paragraph: p)
            } else if let m = trimmed.wholeMatch(of: />\s?(.*)/) {
                closeParagraph(line: n - 1)
                let quote = NSMutableAttributedString(string: "▍ ", attributes: [.font: body, .foregroundColor: NSColor.tertiaryLabelColor])
                quote.append(inline(String(m.1), font: body, color: .secondaryLabelColor, line: n))
                block(quote, line: n, paragraph: style(indent: 4, hang: 14, after: 4))
            } else if let m = line.wholeMatch(of: /(\s*)([-*+]|\d+[.)])\s+(.*)/) {
                closeParagraph(line: n - 1)
                let depth = CGFloat(m.1.count / 2)
                var marker = m.2.first.map { $0.isNumber } == true ? String(m.2) : "•"
                var text = String(m.3)
                if let task = text.wholeMatch(of: /\[([ xX])\]\s+(.*)/) {
                    marker = task.1 == " " ? "☐" : "☑"
                    text = String(task.2)
                }
                let item = NSMutableAttributedString(string: marker + "\t", attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor])
                item.append(inline(text, font: body, line: n))
                let p = style(indent: 6 + depth * 20, hang: 20, after: 3)
                p.tabStops = [NSTextTab(textAlignment: .left, location: 26 + depth * 20)]
                block(item, line: n, paragraph: p)
            } else if trimmed.hasPrefix("|") {
                closeParagraph(line: n - 1)
                block(NSAttributedString(string: trimmed, attributes: [.font: mono, .foregroundColor: NSColor.textColor]),
                      line: n, paragraph: style(after: 0))
            } else {
                // Paragraph text: consecutive lines join with a space, like rendered Markdown.
                let piece = NSMutableAttributedString()
                if openParagraph { piece.append(NSAttributedString(string: " ")) }
                piece.append(inline(trimmed, font: body, line: n))
                let all = NSRange(location: 0, length: piece.length)
                if !openParagraph { paragraphStyle = style(after: 10) }
                gap = false
                piece.addAttribute(.paragraphStyle, value: paragraphStyle, range: all)
                piece.addAttribute(.sourceLine, value: n, range: all)
                out.append(piece)
                openParagraph = true
            }
        }
        closeParagraph(line: max(lines.count, 1))
        return RenderedMarkdown(text: out, headings: headings)
    }

    /// Inclusive 1-based source line range covered by a rendered character range.
    public static func lineRange(of range: NSRange, in text: NSAttributedString) -> ClosedRange<Int>? {
        guard range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        var lo = Int.max, hi = Int.min
        text.enumerateAttribute(.sourceLine, in: range) { value, _, _ in
            if let n = value as? Int { lo = min(lo, n); hi = max(hi, n) }
        }
        return lo <= hi ? lo...hi : nil
    }

    /// Rendered range of the first characters produced by `line`.
    public static func range(ofLine line: Int, in text: NSAttributedString) -> NSRange? {
        var found: NSRange?
        text.enumerateAttribute(.sourceLine, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            if value as? Int == line { found = range; stop.pointee = true }
        }
        return found
    }

    static var codeBackground: NSColor { NSColor.textColor.withAlphaComponent(0.06) }

    static func inline(_ markdown: String, font: NSFont, color: NSColor = .textColor, line: Int) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            var runFont = font
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color, .sourceLine: line]
            if let intent = run.inlinePresentationIntent {
                var traits = runFont.fontDescriptor.symbolicTraits
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                runFont = NSFont(descriptor: runFont.fontDescriptor.withSymbolicTraits(traits), size: runFont.pointSize) ?? runFont
                if intent.contains(.code) {
                    runFont = .monospacedSystemFont(ofSize: font.pointSize * 0.88, weight: .regular)
                    attributes[.backgroundColor] = codeBackground
                }
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            if let url = run.link {
                attributes[.link] = url
                attributes[.foregroundColor] = NSColor.linkColor
            }
            attributes[.font] = runFont
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return out
    }
}
