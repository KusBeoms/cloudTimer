// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CloudTimer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CloudTimer", path: "Sources/CloudTimer")
    ]
)
