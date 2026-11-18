import Foundation
import MDReviewCore
import Testing

/// A temporary folder holding `docs/plan.md`; the store goes in its `store/`.
private func scratch() throws -> (root: URL, file: URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let docs = root.appending(path: "docs", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    let file = docs.appending(path: "plan.md")
    try "# Plan\n\nShip it.\n".write(to: file, atomically: true, encoding: .utf8)
    return (root, file)
}

private let comments = [
    ReviewComment(lines: 3...3, quote: "Ship it.", text: "When?", range: NSRange(location: 6, length: 8))
]

@Test func storeRoundTripsCommentsAndWritesNothingBesideTheFile() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(try store.load(for: file).isEmpty)
    try store.save(comments, for: file)
    #expect(try store.load(for: file) == comments)

    let review = try store.saveReview("# Review", for: file)
    #expect(review.path.hasPrefix(root.appending(path: "store").path))
    #expect(review.lastPathComponent.hasPrefix("plan-") && review.lastPathComponent.hasSuffix(".review.md"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["plan.md"])

    try store.save([], for: file)
    #expect(try store.load(for: file).isEmpty)
}

@Test func storeFindsCommentsAfterTheFileMoves() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    try store.save(comments, for: file)

    let moved = root.appending(path: "renamed.md")
    try FileManager.default.moveItem(at: file, to: moved)
    #expect(try store.load(for: moved) == comments)
    #expect(try store.load(for: moved) == comments)  // rekeyed, so the second load finds it by path
}

@Test func storeKeepsAnUnreadableRecordAndStartsEmpty() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    try store.save(comments, for: file)
    let records = root.appending(path: "store/Comments", directoryHint: .isDirectory)
    let record = try #require(
        try FileManager.default.contentsOfDirectory(at: records, includingPropertiesForKeys: nil).first)
    try Data("{ not json".utf8).write(to: record)

    let error = try #require(throws: ReviewStore.UnreadableRecord.self) { try store.load(for: file) }
    let kept = try #require(error.preservedAt)
    #expect(try String(contentsOf: kept, encoding: .utf8) == "{ not json")

    #expect(try store.load(for: file).isEmpty)
    try store.save(comments, for: file)
    #expect(try String(contentsOf: kept, encoding: .utf8) == "{ not json")
}

@Test func handoffAnswersEachWaitingRequestForTheSentFileOnce() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let other = root.appending(path: "other.md")
    try "Other\n".write(to: other, atomically: true, encoding: .utf8)

    let first = try store.request(file)
    let second = try store.request(file)
    let elsewhere = try store.request(other)
    #expect(store.newestRequest()?.file.lastPathComponent == "other.md")
    #expect(store.takeAnswer(for: first) == nil)

    #expect(store.answer(.review("# Review"), for: file) == 2)
    #expect(store.takeAnswer(for: first) == .review("# Review"))
    #expect(store.takeAnswer(for: second) == .review("# Review"))
    #expect(store.takeAnswer(for: first) == nil)
    #expect(store.takeAnswer(for: elsewhere) == nil)
    #expect(store.answer(.review("# Again"), for: file) == 0)

    #expect(store.answer(.closed, for: other) == 1)
    #expect(store.takeAnswer(for: elsewhere) == .closed)
    #expect(store.newestRequest() == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["plan.md"])
}

@Test func handoffClosesRequestsForEveryOtherFile() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let other = root.appending(path: "other.md")

    let older = try store.request(other)
    let kept = try store.request(file)
    let cutoff = try #require(store.newestRequest())
    #expect(cutoff.file.lastPathComponent == "plan.md")
    let newer = try store.request(other)

    #expect(store.closeRequests(except: file, madeBy: cutoff.date) == 1)
    #expect(store.takeAnswer(for: older) == .closed)
    #expect(store.takeAnswer(for: kept) == nil)
    #expect(store.takeAnswer(for: newer) == nil)

    #expect(store.closeRequests(except: nil, madeBy: .distantFuture) == 2)
    #expect(store.takeAnswer(for: kept) == .closed)
    #expect(store.takeAnswer(for: newer) == .closed)
    #expect(store.newestRequest() == nil)
}

@Test func handoffDropsRequestsWhoseCommandExited() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let gone = Int32.max
    #expect(!ReviewStore.isRunning(gone))

    let id = try store.request(file, from: gone)
    #expect(store.newestRequest() == nil)
    #expect(store.answer(.review("# Review"), for: file) == 0)
    #expect(store.takeAnswer(for: id) == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "store/Handoff").path).isEmpty)
}
