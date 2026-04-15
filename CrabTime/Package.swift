// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CrabTime",
    platforms: [
        .macOS(.v14)
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
