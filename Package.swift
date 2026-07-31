// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EchoNotes",
    platforms: [
        // Core Audio process taps (system audio capture) need macOS 14.2+;
        // we target 15 for a stable baseline.
        .macOS(.v15)
    ],
    products: [
        .executable(name: "EchoNotes", targets: ["EchoNotes"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "EchoNotes",
            dependencies: ["WhisperKit"],
            path: "EchoNotes"
        ),
        .testTarget(
            name: "EchoNotesTests",
            dependencies: ["EchoNotes"],
            path: "EchoNotesTests"
        )
    ]
)
