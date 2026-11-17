// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "mdreview",
    platforms: [.macOS(.v26)],
    products: [
        // Linked by the Xcode app target in project.yml.
        .library(name: "MDReviewCore", targets: ["MDReviewCore"])
    ],
    targets: [
        .target(name: "MDReviewCore"),
        .executableTarget(name: "mdreview", dependencies: ["MDReviewCore"]),
        .testTarget(name: "MDReviewCoreTests", dependencies: ["MDReviewCore"]),
    ]
)
