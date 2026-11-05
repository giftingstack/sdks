// swift-tools-version: 5.9
// Swift 5 language mode on purpose: the package is checked by careful reading and CI, and
// Swift 6 strict concurrency would turn style questions into build failures.
import PackageDescription

let package = Package(
    name: "GiftingStack",
    platforms: [
        .iOS(.v15),
        // Declared so `swift test` runs the Foundation core on a macOS CI host.
        .macOS(.v12),
    ],
    products: [
        .library(name: "GiftingStack", targets: ["GiftingStack"]),
    ],
    targets: [
        .target(
            name: "GiftingStack",
            path: "packages/sdk-ios/Sources/GiftingStack",
            // Apple's privacy manifest: no tracking, no collected data; the elapsed-time clock
            // (ProcessInfo.systemUptime) is a "system boot time" required-reason API (35F9.1).
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "GiftingStackTests",
            dependencies: ["GiftingStack"],
            path: "packages/sdk-ios/Tests/GiftingStackTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
