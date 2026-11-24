# Testing

Tests pin down what mdreview does, not how it does it. A test fails only when a user-visible behavior breaks; a refactor leaves every test unchanged. The rules below come from Google's *Testing on the Toilet* and *Software Engineering at Google* (ch. 11–14).

## What goes where

| Layer | Tool | Tests |
|-------|------|-------|
| `Sources/MDReviewCore/` | Swift Testing (`make test`) | Every behavior of rendering, comments, the store and the export. Most tests live here. |
| `Sources/mdreview/` (SwiftUI) | none directly | Keep views thin. Logic that needs a test moves into `MDReviewCore`. Never test a view's body or hierarchy. |
| The running app | XCUITest (`make uitest`) | The journeys in [journeys.md](journeys.md), plus what only the running app can show, such as a view that crashes. Few and broad. |

Unit tests for a type live in `<Type>Tests.swift`. A long one splits by concern into `<Type>Tests+<Concern>.swift`, the way the source splits.

## Rules

1. **Test behavior through the public API.** `import MDReviewCore`, never `@testable`. Call it the way the app does.
2. **No change-detector tests.** Don't assert on call order, private file layouts, encoder output or anything else a refactor could change without a user noticing. If a refactor breaks a test, fix the test.
3. **Assert on state and output, not interactions.** Check what came back or what changed. Check that a side effect happened only when the side effect is the behavior, such as a review reaching the waiting agent.
4. **One behavior per test.** If a test asserts and then calls the code under test again, split it.
5. **Name the behavior.** One camelCase sentence: subject, outcome, scenario, e.g. `storeFindsCommentsAfterTheFileMoves`. No `testLoad`. An "And" joining two outcomes means two tests.
6. **Arrange, Act, Assert.** Three blocks, in order, separated by one blank line, with one Act. Use `#require` for preconditions and `#expect` for the outcome.
7. **Keep cause next to effect.** Everything that decides the outcome is visible in the test body. No hidden values in shared fixtures.
8. **No logic in tests.** No loops or `if`, and no expected value computed by code. State expected values as literals. For a table of cases use `@Test(arguments:)`.
9. **DAMP over DRY.** Repeat code when that makes the test obvious. Helpers may build values with sensible defaults or assert one conceptual fact. No shared `validate()`, and a nontrivial helper gets its own test.
10. **Real, then fake, then stub.** Use the real type when it is fast and deterministic, including the file system. Otherwise use a small stateful fake at the lowest boundary. No mocking framework.
11. **Hermetic and deterministic.** Each test makes and removes its own temp folder, never reads the real clock for behavior and never sleeps. Tests pass in any order and in parallel.
12. **Push checks down.** Catch a bug with the smallest test that can catch it. UI tests prove the journey works end to end, not every edge case.

## Shape

```swift
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
```

Don't write this. It is a change detector: it checks calls and internal file names, rebuilds the expected value with the code's own encoder, and stays green even if `load` is broken.

```swift
@Test func testSave() throws {
    let fs = SpyFileSystem()
    let store = ReviewStore(directory: tmp, fileSystem: fs)
    try store.save(comments, for: file)
    #expect(fs.calls == ["createDirectory(Comments)", "write(\(sha256(file.path)).json)"])
}
```

## The file system, time and doubles

- **File system:** use the real one. Make `FileManager.default.temporaryDirectory/<UUID>` per test and remove it in `defer` (`addTeardownBlock` in UI tests). Pass it in through `ReviewStore(directory:)`, or `-StoreDirectory` in UI tests. Never touch the user's real store.
- **Time:** when behavior depends on "now", take it as input and pass a fixed date in tests, as `ReviewStore.request(_:from:at:)` does. Never sleep to make time pass.
- **Async:** `await` the result, or use `confirmation` for events. No polling.
- **Doubles:** only for what a test can't run for real, such as other processes, `NSWorkspace`, the pasteboard or the network. Put a one-protocol seam at that boundary and use a fake that records state. Needing two or more doubles in one test means it belongs in a larger test.

## UI tests

- Each journey in [journeys.md](journeys.md) names the test that walks it. Rename both together; `make docs-check` enforces the link.
- Arrange through launch arguments, temp files and the store's public API, never through the user's state.
- Find elements by accessibility identifier or visible label, never by hierarchy path. Index only into elements that share an identifier, such as comment fields in list order.
- Wait with `waitForExistence(timeout:)`, or an `XCTWaiter` expectation for something outside the UI, never with `sleep` or a hand-rolled loop.
- Several act/assert steps are fine here, because the journey is the behavior.

## Review checklist

- [ ] Would this test still pass after a refactor that keeps behavior the same?
- [ ] Does the name state the behavior and its outcome?
- [ ] Is there one Act, with Arrange, Act and Assert separated by blank lines?
- [ ] Is every value that decides the outcome visible in the body, with expected values as literals?
- [ ] Is it real or fake rather than mocked, with no real clock, shared state or sleeps?

## Sources

- Change-detector tests: https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html
- Test behavior, not implementation: https://testing.googleblog.com/2013/08/testing-on-toilet-test-behavior-not.html
- Test behaviors, not methods: https://testing.googleblog.com/2014/04/testing-on-toilet-test-behaviors-not.html
- Descriptive test names: https://testing.googleblog.com/2014/10/testing-on-toilet-writing-descriptive.html
- Keep tests focused: https://testing.googleblog.com/2018/06/testing-on-toilet-keep-tests-focused.html
- Keep cause and effect clear: https://testing.googleblog.com/2017/01/testing-on-toilet-keep-cause-and-effect.html
- Don't put logic in tests: https://testing.googleblog.com/2014/07/testing-on-toilet-dont-put-logic-in.html
- DAMP, not DRY: https://testing.googleblog.com/2019/12/testing-on-toilet-tests-too-dry-make.html
- Avoid mocks for fidelity: https://testing.googleblog.com/2024/02/increase-test-fidelity-by-avoiding-mocks.html
- Fakes: https://testing.googleblog.com/2013/06/testing-on-toilet-fake-your-way-to.html
- Time is random: https://testing.googleblog.com/2008/04/tott-time-is-random.html
- *Software Engineering at Google*, ch. 11–14: https://abseil.io/resources/swe-book/html/ch12.html (and ch11, ch13, ch14)
