import Foundation

/// Agent replies and the queued review, both carried in `Handoff/`; the command never writes `Comments/`,
/// so the app stays the only writer of a comment record.
extension ReviewStore {
    public struct Reply: Codable, Equatable, Sendable {
        public var id: String
        public var text: String
        public var resolve: Bool

        public init(id: String, text: String, resolve: Bool) {
            (self.id, self.text, self.resolve) = (id, text, resolve)
        }
    }

    private struct ReplyFile: Codable {
        var path: String
        var reply: Reply
    }

    /// Posted after a reply is written, so a running app shows it.
    public static let replyNotification = Notification.Name("com.charliecrouse.mdreview.reply")

    private var handoffFolder: URL { directory.appending(path: "Handoff", directoryHint: .isDirectory) }

    /// Leaves a reply to comment `id` (a prefix of its full id) on `file` for the app to merge.
    public func appendReply(file: URL, id: String, text: String, resolve: Bool) throws {
        try FileManager.default.createDirectory(at: handoffFolder, withIntermediateDirectories: true)
        let body = ReplyFile(path: Self.key(for: file), reply: Reply(id: id, text: text, resolve: resolve))
        try JSONEncoder().encode(body).write(
            to: handoffFolder.appending(path: "\(Self.hash(for: file))-\(UUID().uuidString).reply"),
            options: .atomic)
    }

    /// The replies waiting for `file`, oldest first. Taking them deletes them.
    public func takeReplies(for file: URL) -> [Reply] {
        let key = Self.key(for: file)
        let urls =
            (try? FileManager.default.contentsOfDirectory(at: handoffFolder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "reply" }.compactMap { url -> Reply? in
            guard let data = try? Data(contentsOf: url),
                let body = try? JSONDecoder().decode(ReplyFile.self, from: data)
            else { return nil }
            guard body.path == key else { return nil }
            try? FileManager.default.removeItem(at: url)
            return body.reply
        }
    }

    private func pendingURL(for file: URL) -> URL {
        handoffFolder.appending(path: "\(Self.hash(for: file)).pending")
    }

    /// Hands `review` to every command waiting for `file`; with none waiting it is kept for the next one.
    /// Returns whether a command was waiting.
    @discardableResult
    public func deliver(_ review: String, for file: URL) -> Bool {
        if answer(.review(review), for: file) > 0 {
            try? FileManager.default.removeItem(at: pendingURL(for: file))
            return true
        }
        try? FileManager.default.createDirectory(at: handoffFolder, withIntermediateDirectories: true)
        try? Data(review.utf8).write(to: pendingURL(for: file), options: .atomic)
        return false
    }

    /// The review sent while no command waited for `file`. Taking it deletes it.
    public func takePending(for file: URL) -> String? {
        let url = pendingURL(for: file)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return text
    }
}
