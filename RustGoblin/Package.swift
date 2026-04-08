// swift-interface-format-version: 1.0
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RustGoblin",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "RustGoblin",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "RustGoblinTests",
            dependencies: ["RustGoblin"]
        )
    ]
)
