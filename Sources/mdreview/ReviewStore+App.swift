import MDReviewCore
import OSLog

extension ReviewStore {
    /// The store the app and its command line share, or nil when there is no Application Support folder.
    static func forApp() -> ReviewStore? {
        // The UI test passes `-StoreDirectory <dir>` so it stays out of the user's Application Support.
        if let dir = UserDefaults.standard.string(forKey: "StoreDirectory") {
            return ReviewStore(directory: URL(fileURLWithPath: dir, isDirectory: true))
        }
        do {
            return try ReviewStore.standard()
        } catch {
            Logger(subsystem: "com.charliecrouse.mdreview", category: "store")
                .error("No Application Support folder; comments won't be saved: \(error)")
            return nil
        }
    }
}
