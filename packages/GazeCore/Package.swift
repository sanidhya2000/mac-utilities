// swift-tools-version: 5.9
import PackageDescription

/// Pure gaze math and screen geometry, kept out of the app target so it can be
/// tested without a camera, a display, or a running app.
let package = Package(
    name: "GazeCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "GazeCore", targets: ["GazeCore"])],
    targets: [.target(name: "GazeCore", path: "Sources/GazeCore")]
)
