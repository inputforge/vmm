// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "vmm",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "vmm", targets: ["vmm"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/inputforge/qcow2.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "vmm",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "QCOW2", package: "qcow2"),
            ],
            linkerSettings: [
                .linkedFramework("Virtualization")
            ]
        )
    ]
)
