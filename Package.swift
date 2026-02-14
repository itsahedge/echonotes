// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EchoNotes",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EchoNotes", targets: ["EchoNotes"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            sources: [
                "ggml.c",
                "ggml-alloc.c",
                "ggml-backend.c",
                "ggml-quants.c",
                "whisper.cpp"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("GGML_USE_ACCELERATE"),
                .headerSearchPath("include")
            ],
            cxxSettings: [
                .define("GGML_USE_ACCELERATE"),
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedFramework("Accelerate")
            ]
        ),
        .executableTarget(
            name: "EchoNotes",
            dependencies: ["CWhisper"],
            path: "EchoNotes"
        ),
        .testTarget(
            name: "EchoNotesTests",
            dependencies: ["EchoNotes"],
            path: "EchoNotesTests"
        )
    ],
    cxxLanguageStandard: .cxx11
)
