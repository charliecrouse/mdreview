import AppKit
import MDReviewCore
import OSLog
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class ReviewModel {
    var fileURL: URL?
    var rendered = RenderedMarkdown()
    var comments: [ReviewComment] = [] { didSet { saveComments() } }
    var selection = NSRange(location: 0, length: 0)
    var focusedComment: ReviewComment.ID?
    var scrollTarget: NSRange?
    var status: String?
    var error: String?
    /// The open file was deleted or moved away; the last version stays on screen until it comes back.
    var isMissing = false
    @ObservationIgnored private var source = ""
    @ObservationIgnored private var watcher: FileWatcher?

    @ObservationIgnored private let store = ReviewModel.makeStore()
    /// Off while the open file's saved record couldn't be read or moved aside, so saving can't overwrite it.
    @ObservationIgnored private var savesComments = false
    private nonisolated static let log = Logger(subsystem: "com.charliecrouse.mdreview", category: "store")

    var canComment: Bool {
        MarkdownRenderer.lineRange(of: selection, in: rendered.text) != nil
            && MarkdownRenderer.quote(of: selection, in: rendered.text) != nil
    }

    func open(_ url: URL) {
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            if let previous = fileURL, !isOpen(url) { store?.answer(.closed, for: previous) }
            fileURL = url
            self.source = source
            rendered = MarkdownRenderer.render(source)
            status = nil
            comments = loadComments(for: url).map { $0.reanchored(in: rendered.text) }
            sortComments()
            selection = NSRange(location: 0, length: 0)
            focusedComment = nil
            isMissing = false
            watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
        } catch {
            self.error = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Opens the file the newest waiting `mdreview <file>` command asked for, unless it's already open, and
    /// ends the wait of every earlier command asking for another file.
    func openRequestedFile() {
        guard let (url, date) = store?.newestRequest() else { return }
        if !isOpen(url) { open(url) }
        store?.closeRequests(except: fileURL, madeBy: date)
    }

    private func isOpen(_ url: URL) -> Bool {
        fileURL?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
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
        let previous = rendered.text
        rendered = MarkdownRenderer.render(source)
        selection = NSRange(location: 0, length: 0)
        comments = comments.map { $0.reanchored(from: previous, to: rendered.text) }
        sortComments()
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown"), .plainText].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func addComment() {
        guard let comment = ReviewComment(selection: selection, in: rendered.text) else { return }
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

    /// Copies the batched review to the clipboard, saves it in the app's storage and hands it to any
    /// `mdreview <file>` command waiting for it.
    func send() {
        guard let url = fileURL, !comments.isEmpty else { return }
        let review = ReviewExport.markdown(file: url, comments: comments)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(review, forType: .string)
        let handedOff = (store?.answer(.review(review), for: url) ?? 0) > 0
        let copied =
            "\(handedOff ? "Sent to the waiting command and copied" : "Copied") "
            + "\(comments.count) comment\(comments.count == 1 ? "" : "s")"
        guard let store else {
            status = copied
            return
        }
        do {
            let out = try store.saveReview(review, for: url)
            status = "\(copied) · saved \((out.path as NSString).abbreviatingWithTildeInPath)"
        } catch {
            status = "\(copied), but couldn't save the review: \(error.localizedDescription)"
        }
    }

    private func loadComments(for url: URL) -> [ReviewComment] {
        savesComments = store != nil
        do {
            return try store?.load(for: url) ?? []
        } catch {
            savesComments = error.preservedAt != nil
            let kept = error.preservedAt.map { ($0.path as NSString).abbreviatingWithTildeInPath }
            let note = "\(url.path), kept at \(kept ?? "its place"): \(error.underlying)"
            Self.log.error("Unreadable comments for \(note, privacy: .public)")
            status =
                kept.map { "Couldn't read the saved comments; kept them at \($0)" }
                ?? "Couldn't read the saved comments; new comments won't be saved"
            return []
        }
    }

    private func saveComments() {
        guard savesComments, let store, let url = fileURL else { return }
        do {
            try store.save(comments, for: url)
        } catch {
            Self.log.error("Couldn't save comments for \(url.path, privacy: .public): \(error)")
            status = "Couldn't save comments: \(error.localizedDescription)"
        }
    }

    nonisolated static func makeStore() -> ReviewStore? {
        // The UI test passes `-StoreDirectory <dir>` so it stays out of the user's Application Support.
        if let dir = UserDefaults.standard.string(forKey: "StoreDirectory") {
            return ReviewStore(directory: URL(fileURLWithPath: dir, isDirectory: true))
        }
        do {
            return try ReviewStore.standard()
        } catch {
            log.error("No Application Support folder; comments won't be saved: \(error)")
            return nil
        }
    }
}
