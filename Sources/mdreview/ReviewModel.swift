import AppKit
import MDReviewCore
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class ReviewModel {
    var fileURL: URL?
    var rendered = RenderedMarkdown()
    var comments: [ReviewComment] = []
    var selection = NSRange(location: 0, length: 0)
    var focusedComment: ReviewComment.ID?
    var scrollTarget: NSRange?
    var status: String?
    var error: String?
    /// The open file was deleted or moved away; the last version stays on screen until it comes back.
    var isMissing = false
    @ObservationIgnored private var source = ""
    @ObservationIgnored private var watcher: FileWatcher?

    var canComment: Bool {
        MarkdownRenderer.lineRange(of: selection, in: rendered.text) != nil
            && MarkdownRenderer.quote(of: selection, in: rendered.text) != nil
    }

    func open(_ url: URL) {
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            self.source = source
            rendered = MarkdownRenderer.render(source)
            comments = []
            selection = NSRange(location: 0, length: 0)
            focusedComment = nil
            status = nil
            isMissing = false
            watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
        } catch {
            self.error = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Re-renders after an outside edit and moves each comment to follow its text.
    private func reload() {
        guard let url = fileURL else { return }
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            isMissing = !FileManager.default.fileExists(atPath: url.path)
            return
        }
        isMissing = false
        guard source != self.source else { return }
        self.source = source
        rendered = MarkdownRenderer.render(source)
        selection = NSRange(location: 0, length: 0)
        comments = comments.map { $0.reanchored(in: rendered.text) }
        sortComments()
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown"), .plainText].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func addComment() {
        guard let lines = MarkdownRenderer.lineRange(of: selection, in: rendered.text),
            let quote = MarkdownRenderer.quote(of: selection, in: rendered.text)
        else { return }
        let comment = ReviewComment(lines: lines, quote: quote, range: selection)
        comments.append(comment)
        sortComments()
        focusedComment = comment.id
    }

    private func sortComments() {
        comments.sort { ($0.lines.lowerBound, $0.range.location) < ($1.lines.lowerBound, $1.range.location) }
    }

    func delete(_ id: ReviewComment.ID) {
        comments.removeAll { $0.id == id }
        if focusedComment == id { focusedComment = nil }
    }

    func reveal(_ comment: ReviewComment) {
        focusedComment = comment.id
        if !comment.isOutdated { scrollTarget = comment.range }
    }

    func reveal(line: Int) {
        if let range = MarkdownRenderer.range(ofLine: line, in: rendered.text) {
            scrollTarget = NSRange(location: range.location, length: 0)
        }
    }

    /// Copies the batched review to the clipboard and saves it beside the file.
    func send() {
        guard let url = fileURL, !comments.isEmpty else { return }
        let review = ReviewExport.markdown(file: url, comments: comments)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(review, forType: .string)
        let out = ReviewExport.reviewURL(for: url)
        do {
            try review.write(to: out, atomically: true, encoding: .utf8)
            status =
                "Copied \(comments.count) comment\(comments.count == 1 ? "" : "s") · saved \(out.lastPathComponent)"
        } catch {
            status = "Copied to clipboard, but couldn't save \(out.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
