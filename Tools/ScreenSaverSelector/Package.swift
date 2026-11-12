// swift-tools-version: 6.0
import PackageDescription

/// Builds the bundled selection helper without changing the saver or AppKit host's compiler setup.
let package = Package(
    name: "MatrixScreenSaverSelector",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/AerialScreensaver/PaperSaver.git", exact: "0.4.3")
    ],
    targets: [
        .target(
            name: "MatrixScreenSaverSelection",
            dependencies: [.product(name: "PaperSaverKit", package: "PaperSaver")]),
        .executableTarget(
            name: "MatrixScreenSaverSelector",
            dependencies: ["MatrixScreenSaverSelection"]),
        .executableTarget(
            name: "SelectionChecks",
            dependencies: ["MatrixScreenSaverSelection"], path: "Tests/SelectionChecks"),
    ])
