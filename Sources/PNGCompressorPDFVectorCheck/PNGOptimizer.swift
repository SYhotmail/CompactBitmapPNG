import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGOptimizer {
    static func optimize(url: URL, settings: PNGCompressionSettings = PNGCompressionSettings()) throws -> PNGCompressionResult {
        let originalData = try Data(contentsOf: url)

        guard let source = CGImageSourceCreateWithData(originalData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PNGOptimizerError.failedToDecode
        }

        var candidates: [PNGCompressionCandidate] = []

        let losslessData = try encodePNG(from: image)
        candidates.append(
            PNGCompressionCandidate(
                data: losslessData,
                message: "Optimized successfully with a lossless re-encode.",
                strategy: "Lossless re-encode"
            )
        )

        if settings.enableAdaptiveQuantization,
           let quantizedImage = try quantizedImage(from: image, maxColors: settings.quantizationLevel.rawValue) {
            let quantizedData = try encodePNG(from: quantizedImage)
            candidates.append(
                PNGCompressionCandidate(
                    data: quantizedData,
                    message: "Optimized successfully with adaptive color quantization (lossy, \(settings.quantizationLevel.rawValue) colors).",
                    strategy: "Adaptive quantization (\(settings.quantizationLevel.rawValue) colors)"
                )
            )
        }

        guard let bestCandidate = candidates
            .filter({ $0.data.count < originalData.count })
            .min(by: { $0.data.count < $1.data.count }) else {
            return PNGCompressionResult(
                sourceURL: url,
                outputURL: nil,
                originalBytes: originalData.count,
                compressedBytes: nil,
                status: .unchanged,
                message: settings.enableAdaptiveQuantization
                    ? "No smaller PNG variant was produced with the current quantization settings."
                    : "No smaller PNG variant was produced with lossless compression."
            )
        }

        let outputURL = optimizedOutputURL(for: url)
        try bestCandidate.data.write(to: outputURL, options: .atomic)

        return PNGCompressionResult(
            sourceURL: url,
            outputURL: outputURL,
            originalBytes: originalData.count,
            compressedBytes: bestCandidate.data.count,
            status: .optimized,
            message: bestCandidate.message + " Best strategy: \(bestCandidate.strategy)."
        )
    }

    static func quantizedImage(from image: CGImage, maxColors: Int) throws -> CGImage? {
        let rgbaImage = try rgbaImage(from: image)
        let palette = adaptivePalette(from: rgbaImage.pixels, maxColors: maxColors)

        guard palette.count > maxColors else {
            return nil
        }

        let reducedPalette = Array(palette.prefix(maxColors))
        let quantizedPixels = quantize(rgbaImage.pixels, using: reducedPalette)
        return try cgImage(from: quantizedPixels, width: rgbaImage.width, height: rgbaImage.height)
    }

    private static func encodePNG(from image: CGImage) throws -> Data {
        let targetData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            targetData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PNGOptimizerError.failedToCreateDestination
        }

        CGImageDestinationAddImage(destination, image, [:] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw PNGOptimizerError.failedToEncode
        }

        return targetData as Data
    }

    private static func rgbaImage(from image: CGImage) throws -> RGBAImage {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw PNGOptimizerError.failedToCreateBitmapContext
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private static func adaptivePalette(from pixels: [UInt8], maxColors: Int) -> [PaletteColor] {
        var buckets: [UInt32: PaletteBucket] = [:]
        buckets.reserveCapacity(maxColors * 4)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[index + 3]
            let key = bucketKey(
                red: pixels[index],
                green: pixels[index + 1],
                blue: pixels[index + 2],
                alpha: alpha
            )

            buckets[key, default: PaletteBucket()].append(
                red: pixels[index],
                green: pixels[index + 1],
                blue: pixels[index + 2],
                alpha: alpha
            )
        }

        return buckets.values
            .sorted { $0.count > $1.count }
            .map { $0.averageColor }
    }

    private static func quantize(_ pixels: [UInt8], using palette: [PaletteColor]) -> [UInt8] {
        var quantizedPixels = pixels
        var nearestPaletteIndexByBucket: [UInt32: Int] = [:]
        nearestPaletteIndexByBucket.reserveCapacity(1024)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = pixels[index]
            let green = pixels[index + 1]
            let blue = pixels[index + 2]
            let alpha = pixels[index + 3]
            let key = bucketKey(red: red, green: green, blue: blue, alpha: alpha)

            let paletteIndex = nearestPaletteIndexByBucket[key] ?? {
                let value = nearestPaletteColorIndex(
                    red: red,
                    green: green,
                    blue: blue,
                    alpha: alpha,
                    palette: palette
                )
                nearestPaletteIndexByBucket[key] = value
                return value
            }()

            let color = palette[paletteIndex]
            quantizedPixels[index] = color.red
            quantizedPixels[index + 1] = color.green
            quantizedPixels[index + 2] = color.blue
            quantizedPixels[index + 3] = color.alpha
        }

        return quantizedPixels
    }

    private static func nearestPaletteColorIndex(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: UInt8,
        palette: [PaletteColor]
    ) -> Int {
        var bestIndex = 0
        var bestDistance = Int.max

        for (index, color) in palette.enumerated() {
            let redDelta = Int(red) - Int(color.red)
            let greenDelta = Int(green) - Int(color.green)
            let blueDelta = Int(blue) - Int(color.blue)
            let alphaDelta = Int(alpha) - Int(color.alpha)
            let distance = redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta + (alphaDelta * alphaDelta * 2)

            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static func cgImage(from pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            throw PNGOptimizerError.failedToCreateDataProvider
        }

        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw PNGOptimizerError.failedToCreateImage
        }

        return image
    }

    private static func bucketKey(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> UInt32 {
        let alphaKey = UInt32(alpha >> 4)
        let redKey = UInt32(red >> 3)
        let greenKey = UInt32(green >> 2)
        let blueKey = UInt32(blue >> 3)
        return (alphaKey << 16) | (redKey << 11) | (greenKey << 5) | blueKey
    }

    private static func optimizedOutputURL(for url: URL) -> URL {
        let baseName = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        return directory.appendingPathComponent("\(baseName)-optimized.png")
    }
}

private struct PNGCompressionCandidate {
    let data: Data
    let message: String
    let strategy: String
}

private struct RGBAImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

private struct PaletteColor {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private struct PaletteBucket {
    private(set) var count = 0
    private var redTotal = 0
    private var greenTotal = 0
    private var blueTotal = 0
    private var alphaTotal = 0

    mutating func append(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        count += 1
        redTotal += Int(red)
        greenTotal += Int(green)
        blueTotal += Int(blue)
        alphaTotal += Int(alpha)
    }

    var averageColor: PaletteColor {
        PaletteColor(
            red: UInt8(redTotal / max(count, 1)),
            green: UInt8(greenTotal / max(count, 1)),
            blue: UInt8(blueTotal / max(count, 1)),
            alpha: UInt8(alphaTotal / max(count, 1))
        )
    }
}

enum PNGOptimizerError: LocalizedError {
    case failedToDecode
    case failedToCreateDestination
    case failedToEncode
    case failedToCreateBitmapContext
    case failedToCreateDataProvider
    case failedToCreateImage

    var errorDescription: String? {
        switch self {
        case .failedToDecode:
            return "The PNG file could not be decoded."
        case .failedToCreateDestination:
            return "The optimized PNG destination could not be created."
        case .failedToEncode:
            return "The optimized PNG could not be encoded."
        case .failedToCreateBitmapContext:
            return "The optimizer could not create a bitmap context for PNG processing."
        case .failedToCreateDataProvider:
            return "The optimizer could not create a PNG data provider."
        case .failedToCreateImage:
            return "The optimizer could not create the optimized image."
        }
    }
}
