// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TablacusMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TablacusMac"),
        .testTarget(name: "TablacusMacTests", dependencies: ["TablacusMac"]),
    ]
)
