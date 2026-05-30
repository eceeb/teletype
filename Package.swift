// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Teletype",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TeletypeCore", targets: ["TeletypeCore"]),
        .executable(name: "Teletype", targets: ["Teletype"])
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
        .executableTarget(
            name: "Teletype",
            dependencies: ["TeletypeCore"]
        ),
        .testTarget(
            name: "TeletypeCoreTests",
            dependencies: ["TeletypeCore"]
        )
    ]
)
