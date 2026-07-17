// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Emulator",
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
            name: "Emulator",
            dependencies: ["CLibretro"],
            path: "Sources/Emulator",
            linkerSettings: [
                .linkedFramework("GameController"),
                .linkedFramework("AVFAudio"),
            ]
        )
    ]
)
