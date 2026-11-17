import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ReviewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // `swift run mdreview path/to/file.md`; skip `-Key value` defaults pairs.
        var args = CommandLine.arguments.dropFirst()
        while let arg = args.popFirst() {
            if arg.hasPrefix("-") {
                _ = args.popFirst()
                continue
            }
            model.open(URL(fileURLWithPath: arg))
            break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
