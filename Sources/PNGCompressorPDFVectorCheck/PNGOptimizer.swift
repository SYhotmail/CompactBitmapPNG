import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGOptimizer {
    static func optimize(url: URL) throws -> PNGCompressionResult {
        let originalData = try Data(contentsOf: url)

        guard let source = CGImageSourceCreateWithData(originalData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PNGOptimizerError.failedToDecode
        }

        let candidateData = try reencodePNG(from: image)

        guard candidateData.count < originalData.count else {
            return PNGCompressionResult(
                sourceURL: url,
                outputURL: nil,
                originalBytes: originalData.count,
                compressedBytes: nil,
                status: .unchanged,
                message: "No smaller lossless version was produced."
            )
        }

        let outputURL = optimizedOutputURL(for: url)
        try candidateData.write(to: outputURL, options: .atomic)

        return PNGCompressionResult(
            sourceURL: url,
            outputURL: outputURL,
            originalBytes: originalData.count,
            compressedBytes: candidateData.count,
            status: .optimized,
            message: "Optimized successfully."
        )
    }

    private static func reencodePNG(from image: CGImage) throws -> Data {
        let targetData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            targetData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PNGOptimizerError.failedToCreateDestination
        }

        // Re-encoding without the original metadata provides a safe, lossless baseline optimization.
        CGImageDestinationAddImage(destination, image, [:] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw PNGOptimizerError.failedToEncode
        }

        return targetData as Data
    }

    private static func optimizedOutputURL(for url: URL) -> URL {
        let baseName = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        return directory.appendingPathComponent("\(baseName)-optimized.png")
    }
}

enum PNGOptimizerError: LocalizedError {
    case failedToDecode
    case failedToCreateDestination
    case failedToEncode

    var errorDescription: String? {
        switch self {
        case .failedToDecode:
            return "The PNG file could not be decoded."
        case .failedToCreateDestination:
            return "The optimized PNG destination could not be created."
        case .failedToEncode:
            return "The optimized PNG could not be encoded."
        }
    }
}
