// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AsistanKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "AsistanCore", targets: ["AsistanCore"]),
    ],
    targets: [
        .target(name: "AsistanCore"),
        .testTarget(name: "AsistanCoreTests", dependencies: ["AsistanCore"]),
    ]
)
