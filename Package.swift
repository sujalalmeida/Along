// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TileMe",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TileMe", targets: ["TileMe"])],
    targets: [
        .target(name: "TileMeCore"),
        .executableTarget(name: "TileMe", dependencies: ["TileMeCore"]),
        .testTarget(name: "TileMeCoreTests", dependencies: ["TileMeCore"]),
        // Exercise AX failure recovery without controlling real applications.
        .testTarget(name: "TileMeTests", dependencies: ["TileMe"]),
    ],
    swiftLanguageModes: [.v6]
)
