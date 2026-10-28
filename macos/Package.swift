// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeshDrop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MeshDrop", targets: ["MeshDrop"])
    ],
    targets: [
        .target(
            name: "CMeshDrop",
            path: "Sources/CMeshDrop",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MeshDrop",
            dependencies: ["CMeshDrop"],
            path: "Sources/MeshDrop",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(Context.packageDirectory)/Frameworks",
                    "-lmeshdrop"
                ])
            ]
        )
    ]
)
