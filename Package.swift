// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "swift-vm",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "swift-vm", targets: ["swift-vm"])
    ],
    targets: [
        .executableTarget(
            name: "swift-vm",
            linkerSettings: [
                .linkedFramework("Virtualization")
            ]
        )
    ]
)
