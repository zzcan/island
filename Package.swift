// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "island",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "vibe-hook", dependencies: ["IslandCore"]),
        .executableTarget(name: "island", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
