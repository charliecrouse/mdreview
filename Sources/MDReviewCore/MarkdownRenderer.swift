import AppKit

/// Line-oriented Markdown renderer. Each source line is rendered on its own and tagged with
/// `.sourceLine`, so any rendered selection maps back to exact source lines.
/// ponytail: block structure is parsed line by line (headings, lists, quotes, fences, tables, rules);
/// inline spans that cross a soft line break render literally. Swap in swift-markdown if that matters.
public enum MarkdownRenderer {
    public static func render(_ source: String, bodySize: CGFloat = 15) -> RenderedMarkdown {
        var doc = Builder(bodySize: bodySize)
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let n = index + 1
            var line = String(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                doc.toggleFence(line: n)
            } else if doc.inFence {
                doc.fenceLine(line, line: n)
            } else if trimmed.isEmpty {
                doc.blankLine(line: n)
            } else if let m = trimmed.wholeMatch(of: /(#{1,6})\s+(.*?)\s*#*/) {
                doc.heading(level: m.1.count, title: String(m.2), line: n)
            } else if trimmed.wholeMatch(of: /([-*_])(\s*\1){2,}/) != nil {
                doc.rule(line: n)
            } else if let m = trimmed.wholeMatch(of: />\s?(.*)/) {
                doc.quote(String(m.1), line: n)
            } else if let m = line.wholeMatch(of: /(\s*)([-*+]|\d+[.)])\s+(.*)/) {
                doc.listItem(indent: m.1.count, marker: String(m.2), text: String(m.3), line: n)
            } else if trimmed.hasPrefix("|") {
                let isHeader = index + 1 < lines.count && isDivider(String(lines[index + 1]))
                doc.tableRow(trimmed, isHeader: isHeader, line: n)
            } else {
                doc.paragraphLine(trimmed, line: n)
            }
        }
        doc.closeParagraph(line: max(lines.count, 1))
        return RenderedMarkdown(text: doc.out, headings: doc.headings)
    }

    /// Inclusive 1-based source line range covered by a rendered character range.
    public static func lineRange(of range: NSRange, in text: NSAttributedString) -> ClosedRange<Int>? {
        guard range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        var lo = Int.max
        var hi = Int.min
        text.enumerateAttribute(.sourceLine, in: range) { value, _, _ in
            if let n = value as? Int {
                lo = min(lo, n)
                hi = max(hi, n)
            }
        }
        return lo <= hi ? lo...hi : nil
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

    static func cells(_ row: String) -> [String] {
        var row = Substring(row.trimmingCharacters(in: .whitespaces))
        if row.hasPrefix("|") { row = row.dropFirst() }
        if row.hasSuffix("|") { row = row.dropLast() }
        return row.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    static func isDivider(_ row: String) -> Bool {
        row.contains("-") && cells(row).allSatisfy { $0.wholeMatch(of: /:?-+:?/) != nil }
    }

    private struct Builder {
        let out = NSMutableAttributedString()
        var headings: [Heading] = []
        var inFence = false
        let bodySize: CGFloat
        let body: NSFont
        let mono: NSFont
        private var openParagraph = false
        private var gap = false  // a blank line precedes the next block
        private var lastSpacing: CGFloat = 0  // paragraphSpacing of the last block appended
        private var paragraphStyle = NSMutableParagraphStyle()

        init(bodySize: CGFloat) {
            self.bodySize = bodySize
            body = NSFont.systemFont(ofSize: bodySize)
            mono = NSFont.monospacedSystemFont(ofSize: bodySize - 2, weight: .regular)
        }

        func style(indent: CGFloat = 0, hang: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 8)
            -> NSMutableParagraphStyle
        {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.3
            p.firstLineHeadIndent = indent
            p.headIndent = indent + hang
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            return p
        }

        mutating func closeParagraph(line: Int) {
            guard openParagraph else { return }
            out.append(
                NSAttributedString(string: "\n", attributes: [.sourceLine: line, .paragraphStyle: paragraphStyle]))
            openParagraph = false
        }

        mutating func block(_ content: NSAttributedString, line: Int, paragraph: NSMutableParagraphStyle) {
            if gap { paragraph.paragraphSpacingBefore = max(paragraph.paragraphSpacingBefore, 10) }
            gap = false
            let piece = NSMutableAttributedString(attributedString: content)
            piece.append(NSAttributedString(string: "\n"))
            let all = NSRange(location: 0, length: piece.length)
            piece.addAttribute(.paragraphStyle, value: paragraph, range: all)
            piece.addAttribute(.sourceLine, value: line, range: all)
            out.append(piece)
            lastSpacing = paragraph.paragraphSpacing
        }

        mutating func toggleFence(line: Int) {
            closeParagraph(line: line - 1)
            inFence.toggle()
        }

        mutating func fenceLine(_ text: String, line: Int) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: mono, .foregroundColor: NSColor.textColor, .backgroundColor: codeBackground,
            ]
            block(
                NSAttributedString(string: text.isEmpty ? " " : text, attributes: attributes), line: line,
                paragraph: style(indent: 12, after: 0))
        }

        mutating func blankLine(line: Int) {
            closeParagraph(line: line - 1)
            gap = true
        }

        mutating func heading(level: Int, title: String, line: Int) {
            closeParagraph(line: line - 1)
            let sizes: [CGFloat] = [28, 22, 18, 16, 15, 15]
            let size = sizes[level - 1] * bodySize / 15
            let font = NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
            headings.append(Heading(line: line, level: level, title: title))
            block(
                inline(title, font: font, line: line), line: line,
                paragraph: style(before: level <= 2 ? 18 : 12, after: 6))
        }

        mutating func rule(line: Int) {
            closeParagraph(line: line - 1)
            let p = style(after: 10)
            p.alignment = .center
            block(
                NSAttributedString(
                    string: "· · ·", attributes: [.font: body, .foregroundColor: NSColor.tertiaryLabelColor]),
                line: line, paragraph: p)
        }

        mutating func quote(_ text: String, line: Int) {
            closeParagraph(line: line - 1)
            let quote = NSMutableAttributedString(
                string: "▍ ", attributes: [.font: body, .foregroundColor: NSColor.tertiaryLabelColor])
            quote.append(inline(text, font: body, color: .secondaryLabelColor, line: line))
            block(quote, line: line, paragraph: style(indent: 4, hang: 14, after: 4))
        }

        mutating func listItem(indent: Int, marker: String, text: String, line: Int) {
            closeParagraph(line: line - 1)
            let depth = CGFloat(indent / 2)
            var marker = marker.first.map { $0.isNumber } == true ? marker : "•"
            var text = text
            if let task = text.wholeMatch(of: /\[([ xX])\]\s+(.*)/) {
                marker = task.1 == " " ? "☐" : "☑"
                text = String(task.2)
            }
            let item = NSMutableAttributedString(
                string: marker + "\t", attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor])
            item.append(inline(text, font: body, line: line))
            let p = style(indent: 6 + depth * 20, hang: 20, after: 3)
            p.tabStops = [NSTextTab(textAlignment: .left, location: 26 + depth * 20)]
            block(item, line: line, paragraph: p)
        }

        /// Cells on tab stops; the |---| divider row is rendered away.
        mutating func tableRow(_ text: String, isHeader: Bool, line: Int) {
            closeParagraph(line: line - 1)
            if isDivider(text) { return }
            let font = isHeader ? NSFont.systemFont(ofSize: bodySize, weight: .semibold) : body
            let row = cells(text)
            let content = NSMutableAttributedString()
            for (i, cell) in row.enumerated() {
                if i > 0 { content.append(NSAttributedString(string: "\t", attributes: [.font: body])) }
                content.append(inline(cell, font: font, line: line))
            }
            let column: CGFloat = 200
            let p = style(hang: column * CGFloat(row.count - 1), after: 6)
            p.tabStops = (1..<max(row.count, 2)).map {
                NSTextTab(textAlignment: .left, location: column * CGFloat($0))
            }
            block(content, line: line, paragraph: p)
        }

        /// Consecutive lines join with a space, like rendered Markdown.
        mutating func paragraphLine(_ text: String, line: Int) {
            let piece = NSMutableAttributedString()
            if openParagraph { piece.append(NSAttributedString(string: " ")) }
            piece.append(inline(text, font: body, line: line))
            let all = NSRange(location: 0, length: piece.length)
            if !openParagraph { paragraphStyle = style(before: gap && lastSpacing < 10 ? 10 : 0, after: 10) }
            gap = false
            lastSpacing = 10
            piece.addAttribute(.paragraphStyle, value: paragraphStyle, range: all)
            piece.addAttribute(.sourceLine, value: line, range: all)
            out.append(piece)
            openParagraph = true
        }
    }
}
