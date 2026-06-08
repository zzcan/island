// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "island",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "vibe-hook", dependencies: ["IslandCore"]),
        .executableTarget(name: "island", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
