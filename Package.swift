// swift-tools-version: 6.0
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "LiveCaption",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "LiveCaption", targets: ["LiveCaption"])],
    dependencies: [.package(path: "Vendor/FluidAudio")],
    targets: [
        .systemLibrary(name: "CWhisper", path: "CWhisper"),
        .executableTarget(
            name: "LiveCaption",
            dependencies: [
                "CWhisper",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources",
            cSettings: [
                .unsafeFlags([
                    "-I", "Vendor/whisper.cpp/include",
                    "-I", "Vendor/whisper.cpp/ggml/include"
                ])
            ],
            swiftSettings: [.unsafeFlags(["-Xcc", "-I\(root)/CWhisper/include"])],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(root)/Vendor/whisper.cpp/build-livecaption/src",
                    "-L", "\(root)/Vendor/whisper.cpp/build-livecaption/ggml/src",
                    "-L", "\(root)/Vendor/whisper.cpp/build-livecaption/ggml/src/ggml-blas",
                    "-L", "\(root)/Vendor/whisper.cpp/build-livecaption/ggml/src/ggml-metal",
                    "-lwhisper", "-lggml", "-lggml-cpu", "-lggml-blas", "-lggml-metal", "-lggml-base"
                ]),
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit")
            ]
        ),
        .testTarget(name: "LiveCaptionTests", dependencies: ["LiveCaption"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
