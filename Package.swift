// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "mdreview",
    platforms: [.macOS(.v26)],
    products: [
        // Linked by the Xcode app target in project.yml.
        .library(name: "MDReviewCore", targets: ["MDReviewCore"])
    ],
    targets: [
        .target(name: "MDReviewCore", swiftSettings: strict),
        .executableTarget(name: "mdreview", dependencies: ["MDReviewCore"], swiftSettings: strict),
        .testTarget(name: "MDReviewCoreTests", dependencies: ["MDReviewCore"], swiftSettings: strict),
    ]
)
