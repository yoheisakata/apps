// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyOrganizer",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MyOrganizer",
            path: "Sources/MyOrganizer"
        )
    ]
)
