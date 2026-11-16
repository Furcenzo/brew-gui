// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrewGUI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BrewGUI", targets: ["BrewGUI"]),
    ],
    targets: [
        .target(name: "BrewCore"),
        .executableTarget(name: "BrewGUI", dependencies: ["BrewCore"]),
        .testTarget(name: "BrewCoreTests", dependencies: ["BrewCore"]),
    ]
)
