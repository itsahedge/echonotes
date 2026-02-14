// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EchoNotes",
    platforms: [
        .macOS(.v14)
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
