import AppKit
import Markdown

extension MarkdownBuilder {
    struct InlineStyle {
        var font: NSFont
        var color: NSColor
        var bold = false
        var italic = false
        var strike = false
        var link: URL?
    }

    func inlines(of container: Markup, font: NSFont, color: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var line = line(of: container)
        inlines(of: container, InlineStyle(font: font, color: color), line: &line, into: out)
        return out
    }

    /// `line` counts the soft and hard breaks. The parser's inline positions can fall behind after a
    /// backslash break, and a code span hides its line break, so the later of the two wins.
    private func inlines(
        of container: Markup, _ style: InlineStyle, line: inout Int, into out: NSMutableAttributedString
    ) {
        for child in container.children {
            line = max(line, child.range?.lowerBound.line ?? line)
            var inner = style
            switch child {
            case let text as Markdown.Text: out.append(run(text.string, style, line: line))
            case is SoftBreak:
                out.append(run(startsFootnote(after: child) ? "\n" : " ", style, line: line))
                line += 1
            case is LineBreak:
                out.append(run("\u{2028}", style, line: line))
                line += 1
            case let span as InlineCode: out.append(code(span.code, style, line: line))
            case let html as InlineHTML: out.append(code(html.rawHTML, style, line: line))
            case let image as Markdown.Image: out.append(self.image(image, style, line: line))
            case is Emphasis:
                inner.italic = true
                inlines(of: child, inner, line: &line, into: out)
            case is Strong:
                inner.bold = true
                inlines(of: child, inner, line: &line, into: out)
            case is Strikethrough:
                inner.strike = true
                inlines(of: child, inner, line: &line, into: out)
            case let link as Markdown.Link:
                inner.link = url(link.destination)
                if link.childCount == 0 {
                    out.append(run(link.destination ?? "", inner, line: line))
                } else {
                    inlines(of: child, inner, line: &line, into: out)
                }
            default: inlines(of: child, inner, line: &line, into: out)
            }
        }
    }

    /// Two footnotes on adjacent lines parse as one paragraph; the break between them stays a line break.
    private func startsFootnote(after node: Markup) -> Bool {
        var text = ""
        var index = node.indexInParent + 1
        while let next = node.parent?.child(at: index) as? Markdown.Text {
            text += next.string
            index += 1
        }
        return text.prefixMatch(of: /\[\^[^\]\s]+\]:/) != nil
    }

    private func run(_ string: String, _ style: InlineStyle, line: Int) -> NSAttributedString {
        var traits = style.font.fontDescriptor.symbolicTraits
        if style.bold { traits.insert(.bold) }
        if style.italic { traits.insert(.italic) }
        let font =
            NSFont(descriptor: style.font.fontDescriptor.withSymbolicTraits(traits), size: style.font.pointSize)
            ?? style.font
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.color, .sourceLine: line]
        if style.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = style.link {
            attributes[.link] = link
            attributes[.foregroundColor] = NSColor.linkColor
        }
        return NSAttributedString(string: string, attributes: attributes)
    }

    private func code(_ string: String, _ style: InlineStyle, line: Int) -> NSAttributedString {
        let code = NSMutableAttributedString(attributedString: run(string, style, line: line))
        let all = NSRange(location: 0, length: code.length)
        code.addAttribute(
            .font, value: NSFont.monospacedSystemFont(ofSize: style.font.pointSize * 0.88, weight: .regular), range: all
        )
        code.addAttribute(.backgroundColor, value: Self.codeBackground, range: all)
        return code
    }

    /// A local image is drawn inline, scaled to the reading measure; a remote or missing one shows its alt text.
    private func image(_ image: Markdown.Image, _ style: InlineStyle, line: Int) -> NSAttributedString {
        let url = url(image.source)
        if let url, url.isFileURL, let picture = NSImage(contentsOf: url), picture.size.width > 0 {
            let attachment = NSTextAttachment()
            attachment.image = picture
            let scale = min(1, Self.measure / picture.size.width)
            attachment.bounds = CGRect(
                x: 0, y: 0, width: picture.size.width * scale, height: picture.size.height * scale)
            let out = NSMutableAttributedString(attachment: attachment)
            out.addAttribute(.sourceLine, value: line, range: NSRange(location: 0, length: out.length))
            return out
        }
        var alt = style
        alt.italic = true
        alt.color = .secondaryLabelColor
        alt.link = style.link ?? url
        let text = image.plainText.isEmpty ? (image.source ?? "image") : image.plainText
        return run("[\(text)]", alt, line: line)
    }

    /// Resolves a link or image destination against the file's folder; `#anchors` stay as they are.
    private func url(_ destination: String?) -> URL? {
        guard let destination, !destination.isEmpty else { return nil }
        if destination.hasPrefix("#") { return URL(string: destination) }
        return URL(string: destination, relativeTo: baseURL)?.absoluteURL
    }
}
