// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyChat",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MyChat",
            path: "Sources/MyChat"
        )
    ]
)
