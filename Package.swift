// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Colerm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ColermApp",
            targets: ["ColermApp"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/Lakr233/libghostty-spm.git",
            exact: "1.3.2"
        )
    ],
    targets: [
        .executableTarget(
            name: "ColermApp",
            dependencies: [
                .product(name: "GhosttyTerminal", package: "libghostty-spm")
            ],
            path: "Sources/ColermApp"
        ),
        .testTarget(
            name: "ColermAppTests",
            dependencies: ["ColermApp"],
            path: "Tests/ColermAppTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
