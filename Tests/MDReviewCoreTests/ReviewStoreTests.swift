import Foundation
import MDReviewCore
import Testing

/// A fresh folder holding `docs/plan.md`. The caller removes `root`.
func scratch() throws -> (root: URL, file: URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let docs = root.appending(path: "docs", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    let file = docs.appending(path: "plan.md")
    try "# Plan\n\nShip it.\n".write(to: file, atomically: true, encoding: .utf8)
    return (root, file)
}

/// Overwrites the one comment record a store holds, the way a disk fault or a bad hand edit would.
private func damageTheRecord(in root: URL) throws {
    let records = root.appending(path: "store/Comments", directoryHint: .isDirectory)
    let record = try #require(
        try FileManager.default.contentsOfDirectory(at: records, includingPropertiesForKeys: nil).first)
    try Data("{ not json".utf8).write(to: record)
}

@Test func storeLoadsNoCommentsForAFileNeverSaved() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    let loaded = try store.load(for: file)

    #expect(loaded.isEmpty)
}

@Test func storeLoadsTheCommentsSavedForAFile() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let comment = ReviewComment.page(text: "When?")
    try store.save([comment], for: file)

    let loaded = try store.load(for: file)

    #expect(loaded == [comment])
}

@Test func storeLoadsNoCommentsAfterSavingAnEmptyList() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    try store.save([.page(text: "When?")], for: file)
    try store.save([], for: file)

    let loaded = try store.load(for: file)

    #expect(loaded.isEmpty)
}

@Test func savingCommentsWritesNothingBesideTheFile() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    try store.save([.page(text: "When?")], for: file)

    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "docs").path) == ["plan.md"])
}

@Test func storeFindsCommentsAfterTheFileMoves() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let comment = ReviewComment.page(text: "When?")
    try store.save([comment], for: file)
    let moved = root.appending(path: "renamed.md")
    try FileManager.default.moveItem(at: file, to: moved)

    let loaded = try store.load(for: moved)

    #expect(loaded == [comment])
}

@Test func loadingADamagedRecordThrowsAndKeepsItsContents() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    try store.save([.page(text: "When?")], for: file)
    try damageTheRecord(in: root)

    let error = try #require(throws: ReviewStore.UnreadableRecord.self) { try store.load(for: file) }

    let kept = try #require(error.preservedAt)
    #expect(try String(contentsOf: kept, encoding: .utf8) == "{ not json")
}

@Test func loadingAfterADamagedRecordStartsEmpty() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    try store.save([.page(text: "When?")], for: file)
    try damageTheRecord(in: root)
    _ = try? store.load(for: file)

    let loaded = try store.load(for: file)

    #expect(loaded.isEmpty)
}

@Test func savingAfterADamagedRecordLeavesTheKeptCopyAlone() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    try store.save([.page(text: "When?")], for: file)
    try damageTheRecord(in: root)
    let error = try #require(throws: ReviewStore.UnreadableRecord.self) { try store.load(for: file) }
    let kept = try #require(error.preservedAt)

    try store.save([.page(text: "Again")], for: file)

    #expect(try String(contentsOf: kept, encoding: .utf8) == "{ not json")
}

@Test func savedReviewGoesInTheStoreNamedAfterTheFile() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    let review = try store.saveReview("# Review", for: file)

    #expect(review.deletingLastPathComponent().path.hasPrefix(root.appending(path: "store").path))
    #expect(review.lastPathComponent.wholeMatch(of: /plan-[0-9a-f]+\.review\.md/) != nil)
}

@Test func savingAReviewWritesNothingBesideTheFile() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try store.saveReview("# Review", for: file)

    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "docs").path) == ["plan.md"])
}
