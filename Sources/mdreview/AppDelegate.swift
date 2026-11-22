import AppKit
import MDReviewCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ReviewModel()
    // periphery:ignore - held for the app's lifetime; nothing removes the observer
    private var handoffObserver: (any NSObjectProtocol)?
    // periphery:ignore - held for the app's lifetime; nothing removes the observer
    private var replyObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        handoffObserver = DistributedNotificationCenter.default().addObserver(
            forName: ReviewStore.handoffNotification, object: nil, queue: .main
        ) { [model] _ in
            MainActor.assumeIsolated { model.openRequestedFile() }
        }
        replyObserver = DistributedNotificationCenter.default().addObserver(
            forName: ReviewStore.replyNotification, object: nil, queue: .main
        ) { [model] _ in
            MainActor.assumeIsolated { model.applyReplies() }
        }
        // `swift run mdreview path/to/file.md`; skip `-Key value` defaults pairs.
        var args = CommandLine.arguments.dropFirst()
        while let arg = args.popFirst() {
            if arg.hasPrefix("-") {
                _ = args.popFirst()
                continue
            }
            model.open(URL(fileURLWithPath: arg))
            return
        }
        // Launched by `mdreview <file>` rather than with a file argument.
        model.openRequestedFile()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
