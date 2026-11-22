import AppKit

extension MarkdownBuilder {
    /// `[^note]` references become superscript labels; a `[^note]:` definition opening a line keeps its
    /// note as muted text after the label. Code is left alone.
    func styleFootnotes() {
        let pattern = /\[\^([^\]\s]+)\](:?)/
        let string = out.string
        for match in string.matches(of: pattern).reversed() {
            let range = NSRange(match.range, in: string)
            guard !isCode(at: range.location) else { continue }
            let startsLine = range.location == 0 || (string as NSString).character(at: range.location - 1) == 10
            let isDefinition = !match.2.isEmpty && startsLine
            var attributes = out.attributes(at: range.location, effectiveRange: nil)
            attributes[.font] = NSFont.systemFont(ofSize: bodySize * 0.7)
            attributes[.baselineOffset] = bodySize * 0.35
            attributes[.foregroundColor] = NSColor.linkColor
            let label = NSMutableAttributedString(string: String(match.1), attributes: attributes)
            if isDefinition {
                let note = (string as NSString).lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
                out.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: note)
            } else if !match.2.isEmpty {
                label.append(
                    NSAttributedString(
                        string: ":", attributes: out.attributes(at: NSMaxRange(range) - 1, effectiveRange: nil)))
            }
            out.replaceCharacters(in: range, with: label)
        }
    }

    /// Links bare `https://` and `www.` addresses, as GitHub does. Filenames such as `README.md` stay text.
    func linkBareURLs() {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let string = out.string as NSString
        for match in detector.matches(in: out.string, range: NSRange(location: 0, length: string.length)) {
            let text = string.substring(with: match.range).lowercased()
            guard let url = match.url,
                text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("www."),
                out.attribute(.link, at: match.range.location, effectiveRange: nil) == nil,
                !isCode(at: match.range.location)
            else { continue }
            out.addAttributes([.link: url, .foregroundColor: NSColor.linkColor], range: match.range)
        }
    }

    private func isCode(at location: Int) -> Bool {
        let font = out.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        return font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true
    }
}
