// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "CurveFan",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "CurveFan",
            targets: ["CurveFan"]
        ),
        .executable(
            name: "CurveFanHelper",
            targets: ["CurveFanHelper"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CurveFanCore",
            dependencies: [],
            path: "CurveFan",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "CurveFan",
            dependencies: ["CurveFanCore"],
            path: "CurveFanApp",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
            ]
        ),
        .executableTarget(
            name: "CurveFanHelper",
            dependencies: ["CurveFanCore"],
            path: "CurveFanHelper"
        ),
        .testTarget(
            name: "CurveFanTests",
            dependencies: ["CurveFanCore"],
            path: "Tests/CurveFanTests"
        )
    ]
)
