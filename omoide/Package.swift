// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Omoide",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Omoide",
            path: "Sources/Omoide"
        )
    ]
)
