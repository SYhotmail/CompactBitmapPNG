// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "PNGCompressorPDFVectorCheck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PNGCompressorPDFVectorCheck",
            targets: ["PNGCompressorPDFVectorCheck"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.0")
    ],
    targets: [
        .executableTarget(
            name: "PNGCompressorPDFVectorCheck",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                // Embed an Info.plist so macOS sees a main bundle identifier
                // when the SwiftPM app is launched directly.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PNGCompressorPDFVectorCheck/Resources/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "PNGCompressorPDFVectorCheckTests",
            dependencies: [
                "PNGCompressorPDFVectorCheck",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        )
    ]
)
