// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "UsageBar", targets: ["UsageBar"])
    ],
    targets: [
        .executableTarget(
            name: "UsageBar",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "UsageBarTests",
            dependencies: ["UsageBar"]
        )
    ],
    swiftLanguageModes: [.v5]
)
