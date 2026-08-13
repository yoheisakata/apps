// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyNetWorth",
    platforms: [
        // レシートタブの FoundationModels(オンデバイスLLM)が macOS 26 必須。
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "MyNetWorth",
            path: "Sources/MyNetWorth"
        )
    ]
)
