// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsageInsightsApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CodexUsageInsightsApp",
            targets: ["CodexUsageInsightsApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageInsightsApp"
        ),
        .testTarget(
            name: "CodexUsageInsightsAppTests",
            dependencies: [
                "CodexUsageInsightsApp",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
