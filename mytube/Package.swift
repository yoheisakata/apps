// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyTube",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MyTube",
            path: "Sources/MyTube",
            linkerSettings: [
                // AVKit.VideoPlayer (AVPlayerView のブリッジ) は、AVKit.framework がバイナリに
                // 明示的にリンクされていないと、Xcode デバッガ無しで起動した際に
                // 「failed to demangle superclass of VideoPlayerView」で abort() するという
                // 既知の macOS バグ(FB8928032)がある。SPM ビルドには Xcode の
                // 「Link Binary With Libraries」に相当する設定が無いため、ここで明示的に
                // リンクして回避する。
                .linkedFramework("AVKit")
            ]
        )
    ]
)
