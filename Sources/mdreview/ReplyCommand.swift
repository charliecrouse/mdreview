import AppKit
import MDReviewCore

/// `mdreview reply <file> <id> <text> [--resolve]`: answers one comment of a review. `--resolve` only
/// proposes that the comment is handled; the reviewer confirms it.
enum ReplyCommand {
    static func run(_ args: [String]) -> Never {
        let resolve = args.contains("--resolve")
        let words = args.filter { $0 != "--resolve" }
        guard words.count == 3 else { fail("usage: mdreview reply <file.md> <id> <text> [--resolve]") }
        let file = URL(fileURLWithPath: words[0]).standardizedFileURL
        guard let store = ReviewStore.forApp() else { fail("no Application Support folder to reply through") }
        do {
            try store.appendReply(file: file, id: words[1], text: words[2], resolve: resolve)
        } catch {
            fail("couldn't record the reply: \(error.localizedDescription)")
        }
        DistributedNotificationCenter.default().postNotificationName(
            ReviewStore.replyNotification, object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("mdreview: \(message)\n".utf8))
        exit(2)
    }
}
