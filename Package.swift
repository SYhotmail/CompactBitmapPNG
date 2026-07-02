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
            name: "PNGCompressorPDFVectorCheck"
        ),
        .testTarget(
            name: "PNGCompressorPDFVectorCheckTests",
            dependencies: ["PNGCompressorPDFVectorCheck"]
        )
    ]
)
