import AppKit
import MDReviewCore
import OSLog
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class ReviewModel {
    private(set) var fileURL: URL?
    private(set) var rendered = RenderedMarkdown()
    private(set) var comments: [ReviewComment] = [] { didSet { saveComments() } }
    var selection = NSRange(location: 0, length: 0)
    private(set) var focusedComment: ReviewComment.ID?
    var scrollTarget: NSRange?
    var status: String?
    var filter = CommentFilter.all
    /// A command-line `mdreview <file>` is waiting for this file's review.
    private(set) var agentWaiting = false
    var error: String?
    /// The open file was deleted or moved away; the last version stays on screen until it comes back.
    private(set) var isMissing = false
    @ObservationIgnored private var source = ""
    @ObservationIgnored private var watcher: FileWatcher?

    @ObservationIgnored private let store = ReviewStore.forApp()
    /// Off while the open file's saved record couldn't be read or moved aside, so saving can't overwrite it.
    @ObservationIgnored private var savesComments = false
    private static let log = Logger(subsystem: "com.charliecrouse.mdreview", category: "store")

    var canComment: Bool { ReviewComment(selection: selection, in: rendered.text) != nil }

    /// The comments the inspector lists, in document order.
    var visibleComments: [ReviewComment] { comments.filter(filter.includes) }

    /// 1-based number of the focused comment in the full list, as the export numbers it.
    var focusedPosition: Int? {
        comments.firstIndex { $0.id == focusedComment }.map { $0 + 1 }
    }

    func open(_ url: URL) {
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            if let previous = fileURL, !isOpen(url) { store?.answer(.closed, for: previous) }
            fileURL = url
            self.source = source
            rendered = MarkdownRenderer.render(source, baseURL: url.deletingLastPathComponent())
            status = nil
            comments = loadComments(for: url).map { $0.reanchored(in: rendered.text) }
            applyReplies()
            sortComments()
            selection = NSRange(location: 0, length: 0)
            focusedComment = nil
            isMissing = false
            watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
            refreshAgentWaiting()
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
        refreshAgentWaiting()
    }

    // ponytail: checked on open, handoff and send only; a command killed meanwhile shows until the next one.
    private func refreshAgentWaiting() {
        agentWaiting = fileURL.map { store?.isWaiting(for: $0) ?? false } ?? false
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
        rendered = MarkdownRenderer.render(source, baseURL: url.deletingLastPathComponent())
        selection = NSRange(location: 0, length: 0)
        comments = comments.reanchored(from: previous, to: rendered.text)
        sortComments()
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown"), .plainText].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func addComment() {
        guard let comment = ReviewComment(selection: selection, in: rendered.text) else { return }
        insert(comment)
    }

    func addPageComment() {
        insert(.page())
    }

    private func insert(_ comment: ReviewComment) {
        comments.append(comment)
        sortComments()
        if !filter.includes(comment) { filter = .all }
        focusedComment = comment.id
    }

    private func sortComments() {
        comments.sort { ($0.lines.lowerBound, $0.range.location) < ($1.lines.lowerBound, $1.range.location) }
    }

    /// Merges replies the `mdreview reply` command left for the open file into their comments.
    func applyReplies() {
        guard let url = fileURL, let replies = store?.takeReplies(for: url), !replies.isEmpty else { return }
        edit { $0.apply(replies) }
    }

    /// The reviewer's call on whether the comment is handled; an agent's reply alone never closes it.
    func setResolved(_ resolved: Bool, for id: ReviewComment.ID) {
        edit { $0.setResolved(resolved, for: id) }
    }

    /// Empty once the comment is gone, so a field still editing a deleted comment shows nothing.
    func text(of id: ReviewComment.ID) -> String {
        comments.first { $0.id == id }?.text ?? ""
    }

    func setText(_ text: String, for id: ReviewComment.ID) {
        edit { $0.setText(text, for: id) }
    }

    func delete(_ id: ReviewComment.ID) {
        edit { $0.delete(id) }
        if focusedComment == id { focusedComment = nil }
    }

    /// Assigns only a real change, so a field echoing back the text it already shows doesn't rewrite the record.
    private func edit(_ change: (inout [ReviewComment]) -> Void) {
        var edited = comments
        change(&edited)
        if edited != comments { comments = edited }
    }

    func reveal(_ comment: ReviewComment) {
        focusedComment = comment.id
        if !comment.isOutdated && !comment.isPage { scrollTarget = comment.range }
    }

    /// Moves focus `offset` comments along the visible list, wrapping at the ends.
    func step(by offset: Int) {
        let list = visibleComments
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == focusedComment }
        let next = current.map { ($0 + offset + list.count) % list.count } ?? (offset > 0 ? 0 : list.count - 1)
        reveal(list[next])
    }

    func reveal(line: Int) {
        if let range = MarkdownRenderer.range(ofLine: line, in: rendered.text) {
            scrollTarget = NSRange(location: range.location, length: 0)
        }
    }

    /// What Send exports: resolved comments are closed and stay out of the review.
    var unresolvedCount: Int { comments.count { !$0.isResolved } }

    /// Copies the batched review to the clipboard, saves it in the app's storage and hands it to any
    /// `mdreview <file>` command waiting for it.
    func send() {
        let open = comments.filter { !$0.isResolved }
        guard let url = fileURL, !open.isEmpty else { return }
        let review = ReviewExport.markdown(file: url, comments: open)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(review, forType: .string)
        let handedOff = store?.deliver(review, for: url)
        refreshAgentWaiting()
        let lead =
            switch handedOff {
            case true: "Sent to the waiting command and copied"
            case false: "Queued for the next mdreview command and copied"
            case nil: "Copied"
            }
        let copied = "\(lead) \(open.count) comment\(open.count == 1 ? "" : "s")"
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
}
