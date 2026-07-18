// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LocalFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LocalFlow", path: "Sources/LocalFlow")
    ]
)
