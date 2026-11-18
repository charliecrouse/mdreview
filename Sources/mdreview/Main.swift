import SwiftUI

@main
enum Main {
    /// The app bundle's `mdreview` script runs this executable with `--wait <file>` to be the command line.
    @MainActor static func main() {
        let args = CommandLine.arguments.dropFirst()
        if args.first == "--wait" { WaitCommand.run(Array(args.dropFirst())) }
        MDReviewApp.main()
    }
}
