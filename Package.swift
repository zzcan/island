// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "island",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "vibe-hook", dependencies: ["IslandCore"]),
        .executableTarget(
            name: "island",
            dependencies: [
                "IslandCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                // Sparkle.framework is embedded by Scripts/bundle.sh at
                // island.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
