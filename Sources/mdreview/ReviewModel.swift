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
    var filter = CommentFilter.all
    /// A command-line `mdreview <file>` is waiting for this file's review.
    private(set) var agentWaiting = false
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
            rendered = MarkdownRenderer.render(source)
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
        rendered = MarkdownRenderer.render(source)
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
        comments.append(comment)
        sortComments()
        if !filter.includes(comment) { filter = .all }
        focusedComment = comment.id
    }

    func addPageComment() {
        let comment = ReviewComment.page()
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
        comments.apply(replies)
    }

    /// The reviewer's call on whether the comment is handled; an agent's reply alone never closes it.
    func setResolved(_ resolved: Bool, for id: ReviewComment.ID) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        comments[index].isResolved = resolved
        if !resolved { comments[index].agentSaysDone = false }
    }

    func delete(_ id: ReviewComment.ID) {
        comments.removeAll { $0.id == id }
        if focusedComment == id { focusedComment = nil }
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
