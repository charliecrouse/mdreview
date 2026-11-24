import MDReviewCore
import XCTest

final class MDReviewUITests: XCTestCase {
    @MainActor func testToggleSidebarsCommentSendAndReopen() throws {
        let file = try fixture()
        let app = launch(file)
        let window = app.windows.firstMatch

        // Left sidebar: View → Hide/Show Sidebar (⌃⌘S).
        let sidebar = window.descendants(matching: .any)["sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        window.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(sidebar.waitForNonExistence(timeout: 5))
        window.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))

        // Inspector: the toolbar's Comments button.
        let inspector = window.descendants(matching: .any)["inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        window.buttons["toggleInspector"].click()
        XCTAssertTrue(inspector.waitForNonExistence(timeout: 5))
        window.buttons["toggleInspector"].click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        commentOnWholeFile(in: window)

        let saved = try send(from: window, for: file)
        XCTAssertTrue(saved.contains("## 1. fixture.md:1"), saved)
        XCTAssertTrue(saved.contains("Name the flag."), saved)
        let dir = file.deletingLastPathComponent()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["fixture.md", "store"])

        // The comment comes back when the file is reopened.
        app.terminate()
        app.launch()
        let reloaded = app.windows.firstMatch.descendants(matching: .any)["commentField"].firstMatch
        XCTAssertTrue(reloaded.waitForExistence(timeout: 10))
        XCTAssertEqual(reloaded.value as? String, "Name the flag.")
    }

    @MainActor func testOutsideEditsMoveFlagAndSurviveDeletion() throws {
        let file = try fixture()
        let window = launch(file).windows.firstMatch
        commentOnWholeFile(in: window)

        // An outside edit that moves the text carries the comment along.
        try "# Plan\n\nShip the importer behind a feature flag.\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(window.buttons["Plan"].waitForExistence(timeout: 5), "the outline shows the new heading")
        let moved = try send(from: window, for: file)
        XCTAssertTrue(moved.contains("## 1. fixture.md:3 · id"), moved)

        // Rewriting the quoted text flags the comment instead of dropping it.
        let outdated = window.descendants(matching: .any)["outdated"]
        try "# Plan\n\nShip the exporter.\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(outdated.waitForExistence(timeout: 5))

        // Deleting the file shows that state; recreating it reloads, and the comment stays outdated.
        let missing = window.descendants(matching: .any)["fileMissing"]
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        try "Ship the importer behind a feature flag.\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(missing.waitForNonExistence(timeout: 5))
        XCTAssertTrue(outdated.exists)
        let recreated = try send(from: window, for: file)
        XCTAssertTrue(recreated.contains(" (outdated)\n") && recreated.contains("fixture.md:3 · id"), recreated)
    }

    /// What `mdreview <file>` does: leave a request, then launch the app with no file argument.
    @MainActor func testOpensTheRequestedFileAndAnswersOnSend() throws {
        let file = try fixture()
        let handoff = ReviewStore(directory: store(for: file))
        let id = try handoff.request(file)
        let app = XCUIApplication()
        app.launchArguments = ["-StoreDirectory", store(for: file).path] + Self.noRestore
        app.launch()
        let window = app.windows.firstMatch
        commentOnWholeFile(in: window)

        XCTAssertNil(handoff.takeAnswer(for: id))
        _ = try send(from: window, for: file)
        guard case .review(let review) = handoff.takeAnswer(for: id) else { return XCTFail("no review handed off") }
        XCTAssertTrue(review.contains("Name the flag."), review)
    }

    /// With no command waiting, Send queues the review for the next `mdreview <file>`.
    @MainActor func testSendWithNoAgentWaitingQueuesTheReview() throws {
        let file = try fixture()
        let window = launch(file).windows.firstMatch
        commentOnWholeFile(in: window)
        _ = try send(from: window, for: file)

        let queued = ReviewStore(directory: store(for: file)).takePending(for: file)
        XCTAssertTrue(try XCTUnwrap(queued).contains("Name the flag."), queued ?? "")
    }

    /// What `mdreview reply` does: leave a reply file, ring the doorbell. The reviewer confirms it.
    @MainActor func testAgentReplyShowsOnTheCardAndTheReviewerResolvesIt() throws {
        let file = try fixture()
        let window = launch(file).windows.firstMatch
        commentOnWholeFile(in: window)
        let saved = try send(from: window, for: file)
        let id = try XCTUnwrap(saved.firstMatch(of: /id ([0-9a-f]{8})/)?.1)

        try ReviewStore(directory: store(for: file)).appendReply(
            file: file, id: String(id), text: "Named it rollout_v2", resolve: true)
        DistributedNotificationCenter.default().postNotificationName(
            ReviewStore.replyNotification, object: nil, userInfo: nil, deliverImmediately: true)

        let reply = window.descendants(matching: .any)["agentReply"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        let anywhere = { (id: String) in window.descendants(matching: .any)[id].firstMatch }
        XCTAssertTrue(anywhere("agentDone").exists)
        XCTAssertFalse(anywhere("resolved").exists, "a reply alone never closes the comment")

        anywhere("resolve").click()
        XCTAssertTrue(anywhere("resolved").waitForExistence(timeout: 5))
        XCTAssertTrue(anywhere("reopen").exists)
    }

    /// A page comment has no selection: it exports as the whole file, takes an agent reply and resolves.
    @MainActor func testPageCommentExportsRepliesAndResolves() throws {
        let file = try fixture()
        let window = launch(file).windows.firstMatch
        XCTAssertTrue(window.textViews["reader"].waitForExistence(timeout: 10))
        window.typeKey("m", modifierFlags: [.command, .option, .shift])
        let field = window.descendants(matching: .any)["commentField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Add a rollback plan.")

        let saved = try send(from: window, for: file)
        XCTAssertTrue(saved.contains("## 1. fixture.md (whole file) · id"), saved)
        XCTAssertTrue(saved.contains("Add a rollback plan."), saved)
        XCTAssertFalse(saved.contains("\n> "), saved)
        let id = try XCTUnwrap(saved.firstMatch(of: /id ([0-9a-f]{8})/)?.1)

        try ReviewStore(directory: store(for: file)).appendReply(
            file: file, id: String(id), text: "Added one", resolve: true)
        DistributedNotificationCenter.default().postNotificationName(
            ReviewStore.replyNotification, object: nil, userInfo: nil, deliverImmediately: true)
        let anywhere = { (id: String) in window.descendants(matching: .any)[id].firstMatch }
        XCTAssertTrue(anywhere("agentDone").waitForExistence(timeout: 5))
        anywhere("resolve").click()
        XCTAssertTrue(anywhere("resolved").waitForExistence(timeout: 5))
        XCTAssertFalse(anywhere("outdated").exists)
    }

    /// The badge counts open comments, and with every comment resolved there is nothing to send.
    @MainActor func testSendBadgeCountsOpenCommentsAndDisablesWhenAllResolved() throws {
        let file = try fixture()
        let window = launch(file).windows.firstMatch
        commentOnWholeFile(in: window)
        let anywhere = { (id: String) in window.descendants(matching: .any)[id].firstMatch }
        XCTAssertEqual(window.buttons["sendToAgent"].value as? String, "1 open")

        let saved = try send(from: window, for: file)
        let id = try XCTUnwrap(saved.firstMatch(of: /id ([0-9a-f]{8})/)?.1)
        try ReviewStore(directory: store(for: file)).appendReply(
            file: file, id: String(id), text: "Done", resolve: true)
        DistributedNotificationCenter.default().postNotificationName(
            ReviewStore.replyNotification, object: nil, userInfo: nil, deliverImmediately: true)
        XCTAssertTrue(anywhere("agentDone").waitForExistence(timeout: 5))
        anywhere("resolve").click()
        XCTAssertTrue(anywhere("resolved").waitForExistence(timeout: 5))
        XCTAssertFalse(window.buttons["sendToAgent"].isEnabled)
    }

    /// Deleting the last card while its fresh, empty field still has focus.
    @MainActor func testDeletingAFreshEmptyCommentKeepsTheAppRunning() throws {
        let file = try fixture()
        let app = launch(file)
        let window = app.windows.firstMatch
        let fields = editFreshCommentAfterAPageComment(in: window)

        window.buttons.matching(identifier: "Delete comment").element(boundBy: 1).click()
        XCTAssertTrue(fields.element(boundBy: 1).waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(fields.firstMatch.value as? String, "Add a rollback plan.")
    }

    /// An agent's `mdreview <other file>` swaps in a file with fewer comments while the last one is being edited.
    @MainActor func testOpeningAnotherFileWhileEditingACommentKeepsTheAppRunning() throws {
        let file = try fixture()
        let other = file.deletingLastPathComponent().appendingPathComponent("other.md")
        try "# Other\n".write(to: other, atomically: true, encoding: .utf8)
        let handoff = ReviewStore(directory: store(for: file))
        try handoff.save([.page(text: "Other note.")], for: other)
        let app = launch(file)
        let window = app.windows.firstMatch
        let fields = editFreshCommentAfterAPageComment(in: window)

        _ = try handoff.request(other)
        DistributedNotificationCenter.default().postNotificationName(
            ReviewStore.handoffNotification, object: nil, userInfo: nil, deliverImmediately: true)
        XCTAssertTrue(window.buttons["Other"].waitForExistence(timeout: 5), "the outline shows the other file")
        XCTAssertTrue(fields.element(boundBy: 1).waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(fields.firstMatch.value as? String, "Other note.")
    }

    /// A fresh folder holding `fixture.md`, removed when the test ends.
    private func fixture() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("fixture.md")
        try "Ship the importer behind a feature flag.\n".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Launches on `file` with the app's storage in a `store/` folder beside it.
    @MainActor private func launch(_ file: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-StoreDirectory", store(for: file).path] + Self.noRestore + [file.path]
        app.launch()
        return app
    }

    /// After a crash macOS asks whether to reopen windows, which would hide the window from every later test.
    private static let noRestore = ["-ApplePersistenceIgnoreState", "YES"]

    private func store(for file: URL) -> URL {
        file.deletingLastPathComponent().appendingPathComponent("store")
    }

    /// Clicks Send to Agent and returns the review it saves in the app's storage.
    @MainActor private func send(from window: XCUIElement, for file: URL) throws -> String {
        let reviews = store(for: file).appendingPathComponent("Reviews")
        try? FileManager.default.removeItem(at: reviews)
        let send = window.buttons["sendToAgent"]
        XCTAssertTrue(send.isEnabled)
        send.click()
        let review = {
            (try? FileManager.default.contentsOfDirectory(atPath: reviews.path))?.first { $0.hasSuffix(".review.md") }
        }
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in review() != nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed, "no review saved")
        let name = try XCTUnwrap(review())
        XCTAssertNotNil(name.wholeMatch(of: /fixture-[0-9a-f]+\.review\.md/), name)
        return try String(contentsOf: reviews.appendingPathComponent(name), encoding: .utf8)
    }

    /// Adds a page comment with text, then a comment on the fixture's line, and clicks into the new, empty field.
    @MainActor private func editFreshCommentAfterAPageComment(in window: XCUIElement) -> XCUIElementQuery {
        let reader = window.textViews["reader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        window.typeKey("m", modifierFlags: [.command, .option, .shift])
        let fields = window.descendants(matching: .any).matching(identifier: "commentField")
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5))
        fields.firstMatch.click()
        fields.firstMatch.typeText("Add a rollback plan.")
        reader.click()
        reader.typeKey("a", modifierFlags: .command)
        window.typeKey("m", modifierFlags: [.command, .option])
        XCTAssertTrue(fields.element(boundBy: 1).waitForExistence(timeout: 5))
        fields.element(boundBy: 1).click()
        return fields
    }

    /// Selects the fixture's only line and comments on it (⌥⌘M).
    @MainActor private func commentOnWholeFile(in window: XCUIElement) {
        let reader = window.textViews["reader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        reader.click()
        reader.typeKey("a", modifierFlags: .command)
        window.typeKey("m", modifierFlags: [.command, .option])
        let field = window.descendants(matching: .any)["commentField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Name the flag.")
    }
}
