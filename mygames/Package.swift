// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyGames",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "CLibretro",
            path: "Sources/CLibretro",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MyGames",
            dependencies: ["CLibretro"],
            path: "Sources/MyGames",
            linkerSettings: [
                .linkedFramework("GameController"),
                .linkedFramework("AVFAudio"),
            ]
        )
    ]
)
