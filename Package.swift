// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StorageMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StorageCore"),
        .executableTarget(name: "StorageMonitor", dependencies: ["StorageCore"]),
        .testTarget(name: "StorageCoreTests", dependencies: ["StorageCore"]),
    ]
)
