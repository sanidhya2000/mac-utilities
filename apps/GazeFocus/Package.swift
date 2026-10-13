// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GazeFocus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GazeFocus",
            path: "Sources/GazeFocus",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
