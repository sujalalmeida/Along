// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Along",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Along", targets: ["Along"])],
    targets: [
        .target(name: "AlongCore"),
        .executableTarget(name: "Along", dependencies: ["AlongCore"]),
        .testTarget(name: "AlongCoreTests", dependencies: ["AlongCore"]),
        // Exercise AX failure recovery without controlling real applications.
        .testTarget(name: "AlongTests", dependencies: ["Along"]),
    ],
    swiftLanguageModes: [.v6]
)
