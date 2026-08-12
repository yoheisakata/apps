// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicPlayer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MusicPlayer",
            path: "Sources/MusicPlayer"
        )
    ]
)
