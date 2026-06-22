// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacNTFS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacNTFS", targets: ["MacNTFS"]),
        .executable(name: "MacNTFSHelper", targets: ["MacNTFSHelper"]),
    ],
    targets: [
        .executableTarget(
            name: "MacNTFS",
            path: "MacNTFS",
            linkerSettings: [
                .linkedFramework("DiskArbitration"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "MacNTFSHelper",
            path: "MacNTFSHelper"
        ),
        .testTarget(
            name: "MacNTFSTests",
            dependencies: ["MacNTFS"],
            path: "MacNTFSTests"
        ),
    ]
)
