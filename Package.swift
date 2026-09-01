// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeUsageBarCore"),
        .executableTarget(name: "ClaudeUsageBar", dependencies: ["ClaudeUsageBarCore"]),
        .executableTarget(name: "usage-probe", dependencies: ["ClaudeUsageBarCore"]),
        .testTarget(name: "ClaudeUsageBarCoreTests", dependencies: ["ClaudeUsageBarCore"]),
        .testTarget(name: "ClaudeUsageBarTests", dependencies: ["ClaudeUsageBar"]),
    ]
)
