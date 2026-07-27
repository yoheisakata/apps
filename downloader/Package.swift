// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Downloader",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Downloader",
            path: "Sources/Downloader"
        )
    ]
)
