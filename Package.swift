// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "vmm",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "vmm", targets: ["vmm"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "vmm",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            linkerSettings: [
                .linkedFramework("Virtualization")
            ]
        )
    ]
)
