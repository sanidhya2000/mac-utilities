// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GazeFocus",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../packages/GazeCore")],
    targets: [
        .executableTarget(
            name: "GazeFocus",
            dependencies: [.product(name: "GazeCore", package: "GazeCore")],
            path: "Sources/GazeFocus",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
