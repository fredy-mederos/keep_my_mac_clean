// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeepMyMacClean",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KeepMyMacClean", targets: ["KeepMyMacClean"]),
        .executable(name: "kmmc", targets: ["kmmc"]),
    ],
    targets: [
        // All scanning, sizing and cleaning logic. No UI, fully testable.
        .target(name: "CleanerCore"),
        // The menu bar app.
        .executableTarget(name: "KeepMyMacClean", dependencies: ["CleanerCore"]),
        // Read-only CLI to inspect what the app would find (handy while developing).
        .executableTarget(name: "kmmc", dependencies: ["CleanerCore"]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
        // The app's own logic that doesn't touch the disk, like checking GitHub for updates.
        .testTarget(name: "KeepMyMacCleanTests", dependencies: ["KeepMyMacClean"]),
    ]
)
