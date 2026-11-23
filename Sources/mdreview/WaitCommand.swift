import AppKit
import MDReviewCore

/// `mdreview <file>`: opens the file in the app, waits the way `git commit` waits for its editor, and
/// prints the review once the user sends it. Exits 1 if the file is closed, or the app quits, unsent.
enum WaitCommand {
    static func run(_ args: [String]) -> Never {
        if args.first == "reply" { ReplyCommand.run(Array(args.dropFirst())) }
        if args == ["--version"] {
            print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
            exit(0)
        }
        guard args.count == 1, let path = args.first, !path.hasPrefix("-") else {
            fail(
                "usage: mdreview <file.md> | mdreview reply <file.md> <id> <text> [--resolve] | mdreview --version",
                status: 2)
        }
        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.isReadableFile(atPath: file.path) else { fail("can't read \(path)") }
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { fail("run the mdreview script inside mdreview.app") }
        guard let store = ReviewModel.makeStore() else { fail("no Application Support folder to hand off through") }
        // A review sent while no command waited is handed over at once.
        if let review = store.takePending(for: file) {
            print(review, terminator: "")
            exit(0)
        }
        let id: String
        do {
            id = try store.request(file)
        } catch {
            fail("couldn't record the request: \(error.localizedDescription)")
        }
        // A running app opens the file on this; one that's launching finds the request itself.
        DistributedNotificationCenter.default().postNotificationName(
            ReviewStore.handoffNotification, object: nil, userInfo: nil, deliverImmediately: true)
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { running, error in
            guard let pid = running?.processIdentifier else {
                fail("couldn't open mdreview: \(error?.localizedDescription ?? "unknown error")")
            }
            wait(for: id, in: store, appPID: pid, name: file.lastPathComponent)
        }
        dispatchMain()
    }

    // ponytail: polls every 0.2 s; a kqueue on the Handoff folder if that ever shows up in a profile.
    private static func wait(for id: String, in store: ReviewStore, appPID: pid_t, name: String) -> Never {
        while true {
            // Checked again after the app exits, since it may answer and quit between two polls.
            let appRunning = ReviewStore.isRunning(appPID)
            switch store.takeAnswer(for: id) {
            case .review(let review):
                print(review, terminator: "")
                exit(0)
            case .closed:
                fail("\(name) was closed without sending a review")
            case nil where !appRunning:
                fail("mdreview quit without sending a review")
            case nil:
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }

    private static func fail(_ message: String, status: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("mdreview: \(message)\n".utf8))
        exit(status)
    }
}
