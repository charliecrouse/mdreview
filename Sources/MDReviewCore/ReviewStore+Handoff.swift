import Foundation

/// The round trip behind `mdreview <file>`. The command leaves a request in `Handoff/` naming the file and
/// its own process, then waits. On Send the app answers every request for that file with the review;
/// opening another file answers the old file's requests as closed. A request whose process has exited
/// (the command was interrupted) is dropped instead of answered.
extension ReviewStore {
    public enum Answer: Equatable, Sendable {
        case review(String)
        case closed
    }

    /// Posted after a request is made, so a running app opens the requested file.
    public static let handoffNotification = Notification.Name("com.charliecrouse.mdreview.handoff")

    private struct Request: Codable {
        var path: String
        var pid: Int32
        var date: Date
    }

    private var handoff: URL { directory.appending(path: "Handoff", directoryHint: .isDirectory) }

    /// Records that process `pid` waits for the review of `file`; returns the request's id.
    public func request(_ file: URL, from pid: Int32 = getpid()) throws -> String {
        let id = "\(pid)-\(UUID().uuidString)"
        let request = Request(path: Self.key(for: file), pid: pid, date: Date())
        try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
        try JSONEncoder().encode(request).write(to: handoff.appending(path: "\(id).request"), options: .atomic)
        return id
    }

    /// The file the most recent waiting request asked for, and when it asked.
    public func newestRequest() -> (file: URL, date: Date)? {
        liveRequests().max { $0.request.date < $1.request.date }.map {
            (URL(fileURLWithPath: $0.request.path), $0.request.date)
        }
    }

    /// Whether a command is waiting for the review of `file`.
    public func isWaiting(for file: URL) -> Bool {
        let key = Self.key(for: file)
        return liveRequests().contains { $0.request.path == key }
    }

    /// Answers every waiting request for `file` and returns how many there were.
    @discardableResult
    public func answer(_ answer: Answer, for file: URL) -> Int {
        let key = Self.key(for: file)
        return self.answer(answer) { $0.path == key }
    }

    /// Answers every request made by `cutoff` for a file other than `file` as closed, since only one file is
    /// open. Later requests are left for their own notification to open.
    @discardableResult
    public func closeRequests(except file: URL?, madeBy cutoff: Date) -> Int {
        let key = file.map(Self.key(for:))
        return answer(.closed) { $0.path != key && $0.date <= cutoff }
    }

    private func answer(_ answer: Answer, where matches: (Request) -> Bool) -> Int {
        var answered = 0
        for (url, request) in liveRequests() where matches(request) {
            let id = url.deletingPathExtension().lastPathComponent
            let (data, ext) =
                switch answer {
                case .review(let review): (Data(review.utf8), "review")
                case .closed: (Data(), "closed")
                }
            guard (try? data.write(to: handoff.appending(path: "\(id).\(ext)"), options: .atomic)) != nil else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
            answered += 1
        }
        return answered
    }

    /// The answer to request `id` once the app has given one. Taking it deletes it.
    public func takeAnswer(for id: String) -> Answer? {
        let review = handoff.appending(path: "\(id).review")
        if let text = try? String(contentsOf: review, encoding: .utf8) {
            try? FileManager.default.removeItem(at: review)
            return .review(text)
        }
        let closed = handoff.appending(path: "\(id).closed")
        guard (try? FileManager.default.removeItem(at: closed)) != nil else { return nil }
        return .closed
    }

    /// Signal 0 checks that the process exists without touching it.
    public static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Waiting requests, with any whose process has exited, or that can't be read, removed.
    private func liveRequests() -> [(url: URL, request: Request)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: handoff, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "request" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                let request = try? JSONDecoder().decode(Request.self, from: data),
                Self.isRunning(request.pid)
            else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return (url, request)
        }
    }
}
