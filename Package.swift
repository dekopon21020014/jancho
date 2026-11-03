// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mahjon",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MahjongScore", targets: ["MahjongScore"]),
        .executable(name: "MahjonApp", targets: ["MahjonApp"]),
    ],
    targets: [
        .target(name: "MahjongScore"),
        .executableTarget(
            name: "MahjonApp",
            dependencies: ["MahjongScore"]
        ),
        .testTarget(
            name: "MahjongScoreTests",
            dependencies: ["MahjongScore"]
        ),
    ]
)
