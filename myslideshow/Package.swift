// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MySlideshow",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MySlideshow",
            path: "Sources/MySlideshow",
            linkerSettings: [
                // AVPlayerView(AVKit)がバイナリに明示的にリンクされていないと、Xcodeデバッガ無しで
                // 起動した際に「failed to demangle superclass」でabort()する既知のmacOSバグ
                // (FB8928032、mytubeで実機確認済み)がある。SPMビルドにはXcodeの「Link Binary With
                // Libraries」に相当する設定が無いため、ここで明示的にリンクして回避する。
                .linkedFramework("AVKit")
            ]
        )
    ]
)
