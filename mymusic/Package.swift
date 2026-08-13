// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyMusic",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MyMusic",
            path: "Sources/MyMusic"
        )
    ]
)
