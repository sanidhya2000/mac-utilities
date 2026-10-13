// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AFK",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../packages/PowerCore")],
    targets: [
        .executableTarget(
            name: "AFK",
            dependencies: [.product(name: "PowerCore", package: "PowerCore")],
            path: "Sources/AFK",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
