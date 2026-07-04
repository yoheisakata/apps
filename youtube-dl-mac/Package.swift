// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YouTubeDownloader",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "YouTubeDownloader",
            path: "Sources/YouTubeDownloader"
        )
    ]
)
