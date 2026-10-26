// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Biosphere",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Biosphere",
            path: "Sources/Biosphere"
        ),
        .testTarget(
            name: "BiosphereTests",
            dependencies: ["Biosphere"],
            path: "Tests/BiosphereTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
