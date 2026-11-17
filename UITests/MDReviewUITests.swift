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

    @MainActor func testOutsideEditsMoveFlagAndRestoreComments() throws {
        let file = try fixture()
        let window = launch(file).windows.firstMatch
        commentOnWholeFile(in: window)

        // An outside edit that moves the text carries the comment along.
        try "# Plan\n\nShip the importer behind a feature flag.\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(window.buttons["Plan"].waitForExistence(timeout: 5), "the outline shows the new heading")
        let moved = try send(from: window, for: file)
        XCTAssertTrue(moved.contains("## 1. fixture.md:3\n"), moved)

        // Rewriting the quoted text flags the comment instead of dropping it.
        let outdated = window.descendants(matching: .any)["outdated"]
        try "# Plan\n\nShip the exporter.\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(outdated.waitForExistence(timeout: 5))

        // Deleting the file shows that state; recreating it reloads and restores the comment.
        let missing = window.descendants(matching: .any)["fileMissing"]
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        try "Ship the importer behind a feature flag.\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(missing.waitForNonExistence(timeout: 5))
        XCTAssertTrue(outdated.waitForNonExistence(timeout: 5))
        let restored = try send(from: window, for: file)
        XCTAssertTrue(restored.contains("## 1. fixture.md:1\n"), restored)
    }

    private func fixture() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("fixture.md")
        try "Ship the importer behind a feature flag.\n".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Launches on `file` with the app's storage in a `store/` folder beside it.
    @MainActor private func launch(_ file: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-StoreDirectory", store(for: file).path, file.path]
        app.launch()
        return app
    }

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
        let deadline = Date().addingTimeInterval(5)
        var names: [String] = []
        while names.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            names = (try? FileManager.default.contentsOfDirectory(atPath: reviews.path)) ?? []
        }
        let name = try XCTUnwrap(names.first)
        XCTAssertTrue(name.hasPrefix("fixture-") && name.hasSuffix(".review.md"), name)
        return try String(contentsOf: reviews.appendingPathComponent(name), encoding: .utf8)
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
