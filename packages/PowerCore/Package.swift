// swift-tools-version: 5.9
import PackageDescription

/// Process sampling and power-assertion primitives shared by WakeHold and AFK.
/// Kept free of app-specific settings so both can supply their own.
let package = Package(
    name: "PowerCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PowerCore", targets: ["PowerCore"])],
    targets: [.target(name: "PowerCore", path: "Sources/PowerCore")]
)
