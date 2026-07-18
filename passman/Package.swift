// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PassMan",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PassMan",
            path: "Sources/PassMan"
        )
    ]
)
