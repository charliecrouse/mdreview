import XCTest

final class MDReviewUITests: XCTestCase {
    @MainActor func testToggleSidebarsCommentAndSend() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("fixture.md")
        try "Ship the importer behind a feature flag.\n".write(to: file, atomically: true, encoding: .utf8)
        let review = dir.appendingPathComponent("fixture.review.md")

        let app = XCUIApplication()
        app.launchArguments = [file.path]
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
        while !FileManager.default.fileExists(atPath: review.path) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let saved = try String(contentsOf: review, encoding: .utf8)
        XCTAssertTrue(saved.contains("## 1. fixture.md:1"), saved)
        XCTAssertTrue(saved.contains("Name the flag."), saved)
    }
}
