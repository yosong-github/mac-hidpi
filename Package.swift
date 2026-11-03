// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HiDPI",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "HiDPI", targets: ["HiDPI"]),
        .executable(name: "hidpi-appcast", targets: ["hidpi-appcast"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3"),
    ],
    targets: [
        .target(
            name: "HiDPICore",
            path: "Sources/HiDPICore"
        ),
        .target(
            name: "CGVirtualDisplayShim",
            path: "Sources/CGVirtualDisplayShim",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .target(
            name: "HiDPIDisplay",
            dependencies: [
                "HiDPICore",
                "CGVirtualDisplayShim",
            ],
            path: "Sources/HiDPIDisplay",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "HiDPI",
            dependencies: [
                "HiDPICore",
                "HiDPIDisplay",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/HiDPIApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "hidpi-appcast",
            dependencies: ["HiDPICore"],
            path: "Sources/hidpi-appcast"
        ),
        .testTarget(
            name: "HiDPICoreTests",
            dependencies: ["HiDPICore"],
            path: "Tests/HiDPICoreTests"
        ),
    ]
)
