// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Teletype",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TeletypeCore", targets: ["TeletypeCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "TeletypeCore",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .testTarget(
            name: "TeletypeCoreTests",
            dependencies: ["TeletypeCore"]
        )
    ]
)
