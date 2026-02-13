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
    dependencies: [
        // No external dependencies for MVP
    ],
    targets: [
        .executableTarget(
            name: "EchoNotes",
            dependencies: [],
            path: "EchoNotes"
        ),
        .testTarget(
            name: "EchoNotesTests",
            dependencies: ["EchoNotes"],
            path: "EchoNotesTests"
        )
    ]
)
