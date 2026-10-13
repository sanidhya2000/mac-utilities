// swift-tools-version: 5.9
import PackageDescription

/// Unit tests, built as a plain executable.
///
/// XCTest and swift-testing both ship with Xcode, which this project
/// deliberately does not require. A small hand-rolled harness keeps the tests
/// runnable on any machine that can build the apps.
let package = Package(
    name: "UnitTests",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../packages/PowerCore"),
        .package(path: "../packages/GazeCore"),
    ],
    targets: [
        .executableTarget(
            name: "UnitTests",
            dependencies: [
                .product(name: "PowerCore", package: "PowerCore"),
                .product(name: "GazeCore", package: "GazeCore"),
            ],
            path: "Sources/UnitTests"
        )
    ]
)
