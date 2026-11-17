import CryptoKit
import Foundation

/// Keeps each reviewed file's comments, and the reviews sent to an agent, in the app's own
/// storage, so nothing is written into the folder that holds the Markdown.
public struct ReviewStore: Sendable {
    /// A saved record that couldn't be read. It was moved to `preservedAt` so later saves can't
    /// overwrite it; `preservedAt` is nil when even that failed.
    public struct UnreadableRecord: Error {
        public let preservedAt: URL?
        public let underlying: any Error
    }

    private struct Record: Codable {
        // periphery:ignore - records are named by a hash; this tells a person which file one belongs to
        var path: String
        /// Finds the file again after a rename or move, when its path no longer matches.
        var bookmark: Data?
        var comments: [ReviewComment]
    }

    private let directory: URL
    private var records: URL { directory.appending(path: "Comments", directoryHint: .isDirectory) }

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/mdreview/`
    public static func standard() throws -> ReviewStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return ReviewStore(directory: support.appending(path: "mdreview", directoryHint: .isDirectory))
    }

    /// The saved comments for `file`, or none. A record found only through its bookmark (the file
    /// was renamed or moved) is rekeyed to the new path.
    public func load(for file: URL) throws(UnreadableRecord) -> [ReviewComment] {
        let url = recordURL(for: file)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                return try JSONDecoder().decode(Record.self, from: Data(contentsOf: url)).comments
            } catch {
                let aside = url.deletingPathExtension().appendingPathExtension(
                    "unreadable-\(Int(Date().timeIntervalSince1970)).json")
                let moved = (try? FileManager.default.moveItem(at: url, to: aside)) != nil
                throw UnreadableRecord(preservedAt: moved ? aside : nil, underlying: error)
            }
        }
        guard let (old, record) = recordFoundByBookmark(for: file) else { return [] }
        try? FileManager.default.moveItem(at: old, to: url)
        return record.comments
    }

    /// Saves `comments` for `file`, replacing its record; no comments removes the record.
    public func save(_ comments: [ReviewComment], for file: URL) throws {
        let url = recordURL(for: file)
        guard !comments.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let record = Record(path: Self.key(for: file), bookmark: try? file.bookmarkData(), comments: comments)
        try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    /// Writes the review sent to an agent as `Reviews/plan-1a2b3c4d.review.md` and returns where it went.
    /// The hash keeps two `plan.md` files in different folders apart.
    public func saveReview(_ review: String, for file: URL) throws -> URL {
        let reviews = directory.appending(path: "Reviews", directoryHint: .isDirectory)
        let name = "\(file.deletingPathExtension().lastPathComponent)-\(Self.hash(for: file).prefix(8)).review.md"
        try FileManager.default.createDirectory(at: reviews, withIntermediateDirectories: true)
        let url = reviews.appending(path: name)
        try review.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func recordURL(for file: URL) -> URL {
        records.appending(path: "\(Self.hash(for: file)).json")
    }

    // ponytail: linear scan of every record, only when the path has none; index bookmarks if it gets slow.
    private func recordFoundByBookmark(for file: URL) -> (URL, Record)? {
        let key = Self.key(for: file)
        let urls = (try? FileManager.default.contentsOfDirectory(at: records, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                let record = try? JSONDecoder().decode(Record.self, from: data),
                let bookmark = record.bookmark
            else { continue }
            var stale = false
            let resolved = try? URL(
                resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
            if let resolved, Self.key(for: resolved) == key { return (url, record) }
        }
        return nil
    }

    /// Symlinks resolved too, because a resolved bookmark comes back as the real path.
    private static func key(for file: URL) -> String {
        file.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func hash(for file: URL) -> String {
        SHA256.hash(data: Data(key(for: file).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
