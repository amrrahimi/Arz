// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Plowy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Plowy", path: "Sources/Plowy")
    ]
)
