import AppKit
import Markdown

/// Walks a parsed document's blocks into an attributed string for the TextKit 1 reader.
struct MarkdownBuilder {
    /// Where a block sits: inside which quotes, code or table cells, and how far a list indents it.
    struct Context {
        var indent: CGFloat = 0
        var blocks: [NSTextBlock] = []
        /// A list item's marker, drawn in front of the item's first line.
        var marker: String?
        var color = NSColor.textColor
        var spacing: CGFloat = 10
        var listDepth = 0
    }

    let out = NSMutableAttributedString()
    var headings: [Heading] = []
    let baseURL: URL?
    /// The parsed source, for telling fenced code from indented code.
    let lines: [String]
    let bodySize: CGFloat
    let body: NSFont
    let mono: NSFont
    static let markerWidth: CGFloat = 22
    /// About the reader's text width, which images and tables fit within.
    static let measure: CGFloat = 640
    static var codeBackground: NSColor { NSColor.textColor.withAlphaComponent(0.06) }

    init(lines: [String], baseURL: URL?, bodySize: CGFloat) {
        self.lines = lines
        self.baseURL = baseURL
        self.bodySize = bodySize
        body = NSFont.systemFont(ofSize: bodySize)
        mono = NSFont.monospacedSystemFont(ofSize: bodySize - 2, weight: .regular)
    }

    mutating func blocks(of container: Markup, _ context: Context) {
        var context = context
        for child in container.children {
            block(child, context)
            context.marker = nil
        }
        if container is ListItem, container.childCount == 0 {
            paragraph(NSAttributedString(), line: line(of: container), context)
        }
    }

    private mutating func block(_ node: Markup, _ context: Context) {
        if context.blocks.count + context.listDepth >= Self.maxNesting { return sourceLines(of: node, context) }
        var context = context
        if context.marker != nil, !(node is Paragraph || node is Markdown.Heading) {
            paragraph(NSAttributedString(), line: line(of: node), context)
            context.marker = nil
        }
        switch node {
        case let paragraph as Paragraph:
            self.paragraph(inlines(of: paragraph, font: body, color: context.color), line: line(of: node), context)
        case let heading as Markdown.Heading: self.heading(heading, context)
        case let quote as BlockQuote: self.quote(quote, context)
        case let list as ListItemContainer: self.list(list, context)
        case let code as CodeBlock: self.code(code, context)
        case let html as HTMLBlock: verbatim(html.rawHTML, label: nil, firstLine: line(of: node), context)
        case let table as Markdown.Table: self.table(table, context)
        case is ThematicBreak: rule(line: line(of: node), context)
        default: blocks(of: node, context)
        }
    }

    func line(of node: Markup) -> Int { node.range?.lowerBound.line ?? 1 }

    /// Deeper than any real document nests; walking further could overflow the stack on a hostile file.
    static let maxNesting = 32

    /// A block nested past `maxNesting`, shown as its source lines, which takes no further recursion.
    private mutating func sourceLines(of node: Markup, _ context: Context) {
        guard let range = node.range else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: context.color]
        for line in range.lowerBound.line...max(range.lowerBound.line, range.upperBound.line)
        where lines.indices.contains(line - 1) {
            paragraph(NSAttributedString(string: lines[line - 1], attributes: attributes), line: line, context)
        }
    }

    /// The paragraph style of a block at `context`, with a tab stop after a list marker.
    func style(_ context: Context, before: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.3
        style.headIndent = context.indent
        style.firstLineHeadIndent = context.marker == nil ? context.indent : context.indent - Self.markerWidth
        style.tabStops = [NSTextTab(textAlignment: .left, location: context.indent)]
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = context.spacing
        style.textBlocks = context.blocks
        return style
    }

    /// Appends one paragraph, prefixed with any pending list marker. Characters that carry no line yet,
    /// such as the marker and the closing newline, take `line`.
    mutating func paragraph(
        _ content: NSAttributedString, line: Int, _ context: Context, style: NSMutableParagraphStyle? = nil
    ) {
        let piece = NSMutableAttributedString()
        if let marker = context.marker {
            piece.append(
                NSAttributedString(
                    string: marker + "\t", attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        piece.append(content)
        piece.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        let all = NSRange(location: 0, length: piece.length)
        piece.addAttribute(.paragraphStyle, value: style ?? self.style(context), range: all)
        piece.enumerateAttribute(.sourceLine, in: all) { value, range, _ in
            if value == nil { piece.addAttribute(.sourceLine, value: line, range: range) }
        }
        out.append(piece)
    }

    private mutating func heading(_ heading: Markdown.Heading, _ context: Context) {
        let sizes: [CGFloat] = [28, 22, 18, 16, 15, 15]
        let level = min(max(heading.level, 1), 6)
        let font = NSFont.systemFont(ofSize: sizes[level - 1] * bodySize / 15, weight: level <= 2 ? .bold : .semibold)
        headings.append(Heading(line: line(of: heading), level: level, title: heading.plainText))
        var context = context
        context.spacing = 6
        let style = style(context, before: level <= 2 ? 18 : 12)
        paragraph(
            inlines(of: heading, font: font, color: context.color), line: line(of: heading), context, style: style)
    }

    /// A block with a bar down its leading edge; quotes inside quotes nest their bars.
    private mutating func quote(_ quote: BlockQuote, _ context: Context) {
        let bar = Self.textBlock(indent: context.indent)
        bar.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        bar.setBorderColor(.tertiaryLabelColor, for: .minX)
        bar.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        var inner = context
        inner.blocks.append(bar)
        inner.indent = 0
        inner.color = .secondaryLabelColor
        blocks(of: quote, inner)
        separator(line: quote.range?.upperBound.line ?? line(of: quote), context)
    }

    /// A hairline paragraph after a quote, code block or table. Text blocks with equal settings compare
    /// equal, so without it two neighbouring code blocks would draw as one.
    mutating func separator(line: Int, _ context: Context) {
        let style = style(context)
        style.maximumLineHeight = 1
        paragraph(NSAttributedString(), line: line, context, style: style)
    }

    /// Gives the last paragraph of a list or quote the spacing of the block that holds it.
    private func endBlock(spacing: CGFloat) {
        guard out.length > 0,
            let style = out.attribute(.paragraphStyle, at: out.length - 1, effectiveRange: nil) as? NSParagraphStyle,
            style.paragraphSpacing < spacing
        else { return }
        let wider = (style.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        wider.paragraphSpacing = spacing
        let last = (out.string as NSString).paragraphRange(for: NSRange(location: out.length - 1, length: 0))
        out.addAttribute(.paragraphStyle, value: wider, range: last)
    }

    private mutating func list(_ list: ListItemContainer, _ context: Context) {
        var number = Int((list as? OrderedList)?.startIndex ?? 1)
        for item in list.listItems {
            var inner = context
            inner.indent += Self.markerWidth + 4
            inner.spacing = 4
            inner.listDepth += 1
            inner.marker =
                switch item.checkbox {
                case .checked: "☑"
                case .unchecked: "☐"
                case nil where list is OrderedList: "\(number)."
                case nil: ["•", "◦", "▪"][context.listDepth % 3]
                }
            blocks(of: item, inner)
            number += 1
        }
        endBlock(spacing: context.spacing)
    }

    /// Fenced code shows its language above the code. Each code line keeps its own source line: the code
    /// starts on the line after a fence, or on the block's first line when it's indented. Indented code
    /// can't open with a blank line, and its first source line ends with its first code line.
    private mutating func code(_ code: CodeBlock, _ context: Context) {
        let first = line(of: code)
        let firstCode = code.code.prefix { $0 != "\n" }
        let opening = lines.indices.contains(first - 1) ? lines[first - 1] : ""
        let fenced = code.language != nil || firstCode.isEmpty || !opening.hasSuffix(firstCode)
        verbatim(code.code, label: code.language, firstLine: fenced ? first + 1 : first, context)
    }

    /// Code-styled source on a tinted block, never interpreted.
    mutating func verbatim(_ text: String, label: String?, firstLine: Int, _ context: Context) {
        let tint = Self.textBlock(indent: context.indent)
        tint.backgroundColor = Self.codeBackground
        tint.setWidth(10, type: .absoluteValueType, for: .padding)
        var inner = context
        inner.blocks.append(tint)
        inner.indent = 0
        inner.spacing = 0
        let lines = (text.hasSuffix("\n") ? text.dropLast() : Substring(text))
            .split(separator: "\n", omittingEmptySubsequences: false)
        if let label, !label.isEmpty {
            let font = NSFont.systemFont(ofSize: bodySize - 4, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor.secondaryLabelColor,
            ]
            paragraph(NSAttributedString(string: label, attributes: attributes), line: firstLine - 1, inner)
        }
        for (offset, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: NSColor.textColor]
            paragraph(NSAttributedString(string: String(line), attributes: attributes), line: firstLine + offset, inner)
        }
        separator(line: firstLine + lines.count - 1, context)
    }

    /// Leading YAML front matter, as a muted block of its own.
    mutating func frontMatter(_ lines: ArraySlice<String>, firstLine: Int) {
        guard !lines.isEmpty else { return }
        let start = out.length
        verbatim(lines.joined(separator: "\n"), label: nil, firstLine: firstLine, Context())
        out.addAttribute(
            .foregroundColor, value: NSColor.secondaryLabelColor,
            range: NSRange(location: start, length: out.length - start))
    }

    /// A block across the full measure; without a width a text block shrinks to nothing.
    static func textBlock(indent: CGFloat) -> NSTextBlock {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(indent, type: .absoluteValueType, for: .margin, edge: .minX)
        return block
    }

    private mutating func rule(line: Int, _ context: Context) {
        let style = style(context)
        style.alignment = .center
        let dots = NSAttributedString(
            string: "· · ·", attributes: [.font: body, .foregroundColor: NSColor.tertiaryLabelColor])
        paragraph(dots, line: line, context, style: style)
    }
}
