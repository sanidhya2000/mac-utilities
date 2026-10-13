// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WakeHold",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../packages/PowerCore")],
    targets: [
        .executableTarget(
            name: "WakeHold",
            dependencies: [.product(name: "PowerCore", package: "PowerCore")],
            path: "Sources/WakeHold",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
