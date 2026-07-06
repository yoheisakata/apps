// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetWorth",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NetWorth",
            path: "Sources/NetWorth"
        )
    ]
)
