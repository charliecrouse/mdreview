// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "mdreview",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "MDReviewCore"),
        .executableTarget(name: "mdreview", dependencies: ["MDReviewCore"]),
        .executableTarget(name: "mdreview-check", dependencies: ["MDReviewCore"]),
    ]
)
