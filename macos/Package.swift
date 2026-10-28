// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Snowdrop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Snowdrop", targets: ["Snowdrop"])
    ],
    targets: [
        .target(
            name: "CSnowdrop",
            path: "Sources/CSnowdrop",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Snowdrop",
            dependencies: ["CSnowdrop"],
            path: "Sources/Snowdrop",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(Context.packageDirectory)/Frameworks",
                    "-lsnowdrop"
                ])
            ]
        )
    ]
)
