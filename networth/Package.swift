// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetWorth",
    platforms: [
        // レシートタブの FoundationModels(オンデバイスLLM)が macOS 26 必須。
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "NetWorth",
            path: "Sources/NetWorth"
        )
    ]
)
