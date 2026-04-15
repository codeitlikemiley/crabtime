// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CrabTime",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "CrabTime",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CrabTimeTests",
            dependencies: ["CrabTime"]
        )
    ]
)
