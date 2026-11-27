// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Snowdrop",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "SnowdropCore", targets: ["SnowdropCore"]),
        .library(name: "SnowdropBridge", targets: ["SnowdropBridge"]),
        .executable(name: "SnowdropApp", targets: ["SnowdropApp"])
    ],
    targets: [
        .target(
            name: "CSnowdrop",
            path: "Sources/CSnowdrop",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SnowdropCore",
            path: "Sources/SnowdropCore"
        ),
        .target(
            name: "SnowdropBridge",
            dependencies: ["CSnowdrop", "SnowdropCore"],
            path: "Sources/SnowdropBridge",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(Context.packageDirectory)/Frameworks",
                    "-lsnowdrop"
                ])
            ]
        ),
        .executableTarget(
            name: "SnowdropApp",
            dependencies: ["SnowdropCore", "SnowdropBridge"],
            path: "Sources/SnowdropApp",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(Context.packageDirectory)/Frameworks",
                    "-lsnowdrop"
                ])
            ]
        ),
        .testTarget(
            name: "SnowdropCoreTests",
            dependencies: ["SnowdropCore"],
            path: "Tests/SnowdropCoreTests"
        ),
        .testTarget(
            name: "SnowdropBridgeTests",
            dependencies: ["SnowdropBridge", "SnowdropCore"],
            path: "Tests/SnowdropBridgeTests",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(Context.packageDirectory)/Frameworks",
                    "-lsnowdrop"
                ])
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
