import AppKit

extension MarkdownRenderer {
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
                runFont =
                    NSFont(descriptor: runFont.fontDescriptor.withSymbolicTraits(traits), size: runFont.pointSize)
                    ?? runFont
                if intent.contains(.code) {
                    runFont = .monospacedSystemFont(ofSize: font.pointSize * 0.88, weight: .regular)
                    attributes[.backgroundColor] = codeBackground
                }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
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
