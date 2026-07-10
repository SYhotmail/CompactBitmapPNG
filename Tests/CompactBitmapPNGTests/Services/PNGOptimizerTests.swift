@testable import CompactBitmapPNG
import CoreGraphics
import Testing

@Suite("PNG Optimizer")
struct PNGOptimizerTests {
    @Test("Adaptive quantization reduces a high-color image to the requested palette size")
    func adaptiveQuantizationReducesColorCount() throws {
        let image = try makeGradientImage(width: 24, height: 24)
        let quantizedCandidate = try PNGOptimizer.quantizedImage(from: image, maxColors: 16)
        let quantized = try #require(quantizedCandidate)
        let colors = try rgbaColors(in: quantized)

        #expect(colors.count <= 16)
    }

    private func makeGradientImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((x * 11 + y * 7) % 256)
                pixels[offset + 1] = UInt8((x * 5 + y * 13) % 256)
                pixels[offset + 2] = UInt8((x * 17 + y * 3) % 256)
                pixels[offset + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let image = context.makeImage() else {
            throw TestImageError.failedToCreateImage
        }

        return image
    }

    private func rgbaColors(in image: CGImage) throws -> Set<UInt32> {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw TestImageError.failedToCreateContext
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var colors: Set<UInt32> = []
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = UInt32(pixels[index]) << 24
            let green = UInt32(pixels[index + 1]) << 16
            let blue = UInt32(pixels[index + 2]) << 8
            let alpha = UInt32(pixels[index + 3])
            let value = red | green | blue | alpha
            colors.insert(value)
        }

        return colors
    }
}

private enum TestImageError: Error {
    case failedToCreateContext
    case failedToCreateImage
}
