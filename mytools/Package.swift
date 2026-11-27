// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyTools",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MyTools",
            path: "Sources/MyTools"
        )
    ]
)
