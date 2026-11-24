import Foundation
import MDReviewCore
import Testing

@Test func requestingWritesNothingBesideTheFile() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try store.request(file)

    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "docs").path) == ["plan.md"])
}

@Test func newestRequestNamesTheFileAskedForLast() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let other = root.appending(path: "other.md")
    _ = try store.request(file, at: Date(timeIntervalSince1970: 100))
    _ = try store.request(other, at: Date(timeIntervalSince1970: 200))

    let newest = store.newestRequest()

    #expect(newest?.file.lastPathComponent == "other.md")
    #expect(newest?.date == Date(timeIntervalSince1970: 200))
}

@Test func newestRequestIsNilOnceEveryRequestIsAnswered() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try store.request(file)
    store.answer(.closed, for: file)

    let newest = store.newestRequest()

    #expect(newest == nil)
}

@Test func requestHasNoAnswerBeforeTheAppAnswers() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let id = try store.request(file)

    let answer = store.takeAnswer(for: id)

    #expect(answer == nil)
}

@Test func answeringAFileAnswersEveryRequestForIt() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try store.request(file)
    let second = try store.request(file)

    let answered = store.answer(.review("# Review"), for: file)

    #expect(answered == 2)
    #expect(store.takeAnswer(for: first) == .review("# Review"))
    #expect(store.takeAnswer(for: second) == .review("# Review"))
}

@Test func answeringAFileLeavesRequestsForOtherFilesWaiting() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let other = root.appending(path: "other.md")
    let elsewhere = try store.request(other)

    store.answer(.review("# Review"), for: file)

    #expect(store.takeAnswer(for: elsewhere) == nil)
    #expect(store.isWaiting(for: other))
}

@Test func answeringAFileNobodyWaitsForAnswersNoRequest() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    let answered = store.answer(.review("# Review"), for: file)

    #expect(answered == 0)
}

@Test func answerIsTakenOnlyOnce() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let id = try store.request(file)
    store.answer(.review("# Review"), for: file)
    _ = store.takeAnswer(for: id)

    let again = store.takeAnswer(for: id)

    #expect(again == nil)
}

@Test func closedAnswerReachesTheWaitingRequest() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let id = try store.request(file)

    store.answer(.closed, for: file)

    #expect(store.takeAnswer(for: id) == .closed)
}

@Test func closingRequestsClosesOnlyOtherFilesRequestsMadeByTheCutoff() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let other = root.appending(path: "other.md")
    let older = try store.request(other, at: Date(timeIntervalSince1970: 100))
    let kept = try store.request(file, at: Date(timeIntervalSince1970: 200))
    let newer = try store.request(other, at: Date(timeIntervalSince1970: 300))

    let closed = store.closeRequests(except: file, madeBy: Date(timeIntervalSince1970: 200))

    #expect(closed == 1)
    #expect(store.takeAnswer(for: older) == .closed)
    #expect(store.takeAnswer(for: kept) == nil)
    #expect(store.takeAnswer(for: newer) == nil)
}

@Test func closingRequestsWithNoFileOpenClosesEveryRequestMadeByTheCutoff() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try store.request(file, at: Date(timeIntervalSince1970: 100))
    let second = try store.request(root.appending(path: "other.md"), at: Date(timeIntervalSince1970: 200))

    let closed = store.closeRequests(except: nil, madeBy: Date(timeIntervalSince1970: 200))

    #expect(closed == 2)
    #expect(store.takeAnswer(for: first) == .closed)
    #expect(store.takeAnswer(for: second) == .closed)
}

@Test func exitedProcessIsNotRunning() {
    let running = ReviewStore.isRunning(Int32.max)

    #expect(!running)
}

@Test func requestFromAnExitedCommandIsNotWaiting() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try store.request(file, from: Int32.max)

    let newest = store.newestRequest()

    #expect(newest == nil)
    #expect(!store.isWaiting(for: file))
}

@Test func answeringAFileWhoseCommandExitedAnswersNoRequest() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    let id = try store.request(file, from: Int32.max)

    let answered = store.answer(.review("# Review"), for: file)

    #expect(answered == 0)
    #expect(store.takeAnswer(for: id) == nil)
}

@Test func storeIsNotWaitingForAFileNobodyRequested() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    let waiting = store.isWaiting(for: file)

    #expect(!waiting)
}

@Test func storeIsWaitingOnlyForTheRequestedFile() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try store.request(file)

    #expect(store.isWaiting(for: file))
    #expect(!store.isWaiting(for: root.appending(path: "other.md")))
}

@Test func storeStopsWaitingOnceTheRequestIsAnswered() throws {
    let (root, file) = try scratch()
    let store = ReviewStore(directory: root.appending(path: "store", directoryHint: .isDirectory))
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try store.request(file)

    store.answer(.closed, for: file)

    #expect(!store.isWaiting(for: file))
}
