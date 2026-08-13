// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyDownloader",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MyDownloader",
            path: "Sources/MyDownloader"
        )
    ]
)
