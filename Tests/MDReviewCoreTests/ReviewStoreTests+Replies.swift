import Foundation
import MDReviewCore
import Testing

@Test func repliesComeBackForTheirFile() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    try store.appendReply(file: file, id: "1a2b3c4d", text: "Renamed", resolve: true)
    try store.appendReply(file: root.appending(path: "other.md"), id: "ffffffff", text: "Elsewhere", resolve: false)

    let replies = store.takeReplies(for: file)

    #expect(replies == [ReviewStore.Reply(id: "1a2b3c4d", text: "Renamed", resolve: true)])
}

@Test func takingRepliesLeavesOtherFilesRepliesWaiting() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let other = root.appending(path: "other.md")
    try store.appendReply(file: file, id: "1a2b3c4d", text: "Renamed", resolve: true)
    try store.appendReply(file: other, id: "ffffffff", text: "Elsewhere", resolve: false)
    _ = store.takeReplies(for: file)

    let replies = store.takeReplies(for: other)

    #expect(replies == [ReviewStore.Reply(id: "ffffffff", text: "Elsewhere", resolve: false)])
}

@Test func repliesAreTakenOnlyOnce() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    try store.appendReply(file: file, id: "1a2b3c4d", text: "Renamed", resolve: true)
    _ = store.takeReplies(for: file)

    let again = store.takeReplies(for: file)

    #expect(again.isEmpty)
}

@Test func replyNeverChangesTheSavedComments() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let comment = ReviewComment.page(text: "When?")
    try store.save([comment], for: file)

    try store.appendReply(file: file, id: comment.shortID, text: "Tomorrow", resolve: true)

    #expect(try store.load(for: file) == [comment])
}

@Test func reviewSentWithNoCommandWaitingIsQueued() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    let delivered = store.deliver("# First", for: file)

    #expect(!delivered)
    #expect(store.takePending(for: file) == "# First")
}

@Test func newerQueuedReviewReplacesTheOlderOne() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    store.deliver("# First", for: file)

    store.deliver("# Second", for: file)

    #expect(store.takePending(for: file) == "# Second")
}

@Test func nothingIsQueuedForAFileNeverSent() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    let pending = store.takePending(for: file)

    #expect(pending == nil)
}

@Test func queuedReviewIsTakenOnlyOnce() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    store.deliver("# First", for: file)
    _ = store.takePending(for: file)

    let again = store.takePending(for: file)

    #expect(again == nil)
}

@Test func reviewSentToAWaitingCommandReachesIt() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let id = try store.request(file)

    let delivered = store.deliver("# Live", for: file)

    #expect(delivered)
    #expect(store.takeAnswer(for: id) == .review("# Live"))
}

@Test func reviewSentToAWaitingCommandClearsTheQueuedOne() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    store.deliver("# Stale", for: file)
    _ = try store.request(file)

    store.deliver("# Live", for: file)

    #expect(store.takePending(for: file) == nil)
}
