// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FindMyRing",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        // Static so the app and the widget extension each link the kit (and
        // BigInt) directly, with no dynamic framework to embed — otherwise the
        // extension can't resolve them and the system drops the widget.
        .library(name: "FindMyRingKit", type: .static, targets: ["FindMyRingKit"]),
        .executable(name: "ringcli", targets: ["ringcli"]),
    ],
    dependencies: [
        // Pure-Swift arbitrary-precision integers for the 2048-bit SRP modexp.
        // MIT, mature, last tagged long before this project.
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
    ],
    targets: [
        .target(
            name: "FindMyRingKit",
            dependencies: [
                .product(name: "BigInt", package: "BigInt"),
            ]
        ),
        .executableTarget(
            name: "ringcli",
            dependencies: ["FindMyRingKit"]
        ),
        .testTarget(
            name: "FindMyRingKitTests",
            dependencies: ["FindMyRingKit"]
        ),
    ]
)
