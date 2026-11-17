import XCTest

final class MDReviewUITests: XCTestCase {
    @MainActor func testToggleSidebarsCommentSendAndReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("fixture.md")
        try "Ship the importer behind a feature flag.\n".write(to: file, atomically: true, encoding: .utf8)
        let store = dir.appendingPathComponent("store")
        let reviews = store.appendingPathComponent("Reviews")

        let app = XCUIApplication()
        app.launchArguments = ["-StoreDirectory", store.path, file.path]
        app.launch()
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

        // Select the fixture's only line and comment on it (⌥⌘M).
        let reader = window.textViews["reader"]
        reader.click()
        reader.typeKey("a", modifierFlags: .command)
        window.typeKey("m", modifierFlags: [.command, .option])
        let field = window.descendants(matching: .any)["commentField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Name the flag.")

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
        let saved = try String(contentsOf: reviews.appendingPathComponent(name), encoding: .utf8)
        XCTAssertTrue(saved.contains("## 1. fixture.md:1"), saved)
        XCTAssertTrue(saved.contains("Name the flag."), saved)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["fixture.md", "store"])

        // The comment comes back when the file is reopened.
        app.terminate()
        app.launch()
        let reloaded = app.windows.firstMatch.descendants(matching: .any)["commentField"].firstMatch
        XCTAssertTrue(reloaded.waitForExistence(timeout: 10))
        XCTAssertEqual(reloaded.value as? String, "Name the flag.")
    }
}
