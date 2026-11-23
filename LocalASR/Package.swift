// swift-tools-version: 6.0
// FnVoice on-device transcription engine: NVIDIA Parakeet TDT 0.6B v3 on the Neural Engine,
// through FluidAudio (Apache 2.0). Built as a dynamic library that build.sh embeds in the app.
import PackageDescription

let package = Package(
    name: "ParakeetKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ParakeetKit", type: .dynamic, targets: ["ParakeetKit"])
    ],
    dependencies: [
        // Pinned version: change the commit only after a full new test.
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 revision: "2fcece785efc38dd9f3f0a49dec5545f36d6c1af")
    ],
    targets: [
        .target(
            name: "ParakeetKit",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Stable interface: the app can import ParakeetKit without seeing FluidAudio's modules.
                .unsafeFlags(["-enable-library-evolution", "-emit-module-interface"])
            ]
        )
    ]
)
