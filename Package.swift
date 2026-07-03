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
    targets: [
        .executableTarget(
            name: "PNGCompressorPDFVectorCheck",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed an Info.plist so macOS sees a main bundle identifier
                // when the SwiftPM app is launched directly.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PNGCompressorPDFVectorCheck/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "PNGCompressorPDFVectorCheckTests",
            dependencies: ["PNGCompressorPDFVectorCheck"]
        )
    ]
)
