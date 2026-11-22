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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "MDReviewCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: strict),
        .executableTarget(name: "mdreview", dependencies: ["MDReviewCore"], swiftSettings: strict),
        .testTarget(name: "MDReviewCoreTests", dependencies: ["MDReviewCore"], swiftSettings: strict),
    ]
)
