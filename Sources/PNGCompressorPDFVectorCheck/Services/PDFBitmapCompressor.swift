import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Recompresses the embedded bitmap(s) of a PDF whose pages are pure images (no vector/text
/// content) and rebuilds the PDF from the recompressed images. `CGPDFDocument` is read-only —
/// there's no public API to patch a single embedded image in place — so the only way to do this
/// with Apple frameworks is to redraw each page from scratch into a freshly written PDF, which
/// would silently destroy any vector/text content on a page. To keep that safe, this only acts
/// when every page already has exactly one image XObject and nothing else; anything more
/// complex (mixed pages, multiple images per page, unsupported image formats) is left unchanged.
enum PDFBitmapCompressor {
    static func compress(url: URL, settings: CompressionSettings) throws -> PDFCompressionResult {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw PDFVectorAnalyzerError.failedToOpen
        }

        let originalBytes = (try? url.fileSizeInBytes()) ?? 0
        let pageCount = document.numberOfPages

        var pages: [QualifyingPage] = []
        for pageIndex in 1...pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let state = PDFVectorAnalyzer.scan(page: page)

            guard
                !state.hasVectorContent,
                !state.hasText,
                state.imageXObjectNames.count == 1,
                let imageName = state.imageXObjectNames.first,
                let stream = state.imageStream(named: imageName)
            else {
                return PDFCompressionResult(
                    sourceURL: url,
                    outputURL: nil,
                    originalBytes: originalBytes,
                    compressedBytes: nil,
                    status: .unchanged,
                    message: L10n.string("pdf.compression.unchanged.notEligible")
                )
            }

            pages.append(QualifyingPage(mediaBox: page.getBoxRect(.mediaBox), stream: stream))
        }

        var recompressedPages: [RecompressedPage] = []
        for page in pages {
            guard let image = extractImage(from: page.stream) else {
                return PDFCompressionResult(
                    sourceURL: url,
                    outputURL: nil,
                    originalBytes: originalBytes,
                    compressedBytes: nil,
                    status: .unchanged,
                    message: L10n.string("pdf.compression.unchanged.unsupportedFormat")
                )
            }

            recompressedPages.append(RecompressedPage(mediaBox: page.mediaBox, image: bestImage(for: image, settings: settings)))
        }

        guard let rebuiltData = rebuildPDF(pages: recompressedPages), UInt64(rebuiltData.count) < originalBytes else {
            return PDFCompressionResult(
                sourceURL: url,
                outputURL: nil,
                originalBytes: originalBytes,
                compressedBytes: nil,
                status: .unchanged,
                message: L10n.string("pdf.compression.unchanged.noSmaller")
            )
        }

        let outputURL = settings.overwriteOriginal ? url : optimizedOutputURL(for: url)
        try rebuiltData.write(to: outputURL, options: .atomic)

        return PDFCompressionResult(
            sourceURL: url,
            outputURL: outputURL,
            originalBytes: originalBytes,
            compressedBytes: UInt64(rebuiltData.count),
            status: .compressed,
            message: L10n.string("pdf.compression.success")
        )
    }

    /// Picks the smaller of a lossless re-encode and (if enabled) an adaptively-quantized
    /// re-encode, reusing `PNGOptimizer`'s palette-quantization logic directly.
    private static func bestImage(for image: CGImage, settings: CompressionSettings) -> CGImage {
        guard
            let quantizationLevel = settings.quantizationLevel,
            let quantized = try? PNGOptimizer.quantizedImage(from: image, maxColors: quantizationLevel.rawValue),
            let quantizedData = try? encodePNG(from: quantized),
            let originalData = try? encodePNG(from: image),
            quantizedData.count < originalData.count
        else {
            return image
        }

        return quantized
    }

    private static func extractImage(from stream: CGPDFStreamRef) -> CGImage? {
        var format: CGPDFDataFormat = .raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { return nil }

        switch format {
        case .jpegEncoded:
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)

        case .raw:
            return decodeRawImage(data: data, stream: stream)

        default:
            return nil
        }
    }

    /// Handles 8-bit-per-component DeviceGray/DeviceRGB images (including ICCBased color spaces
    /// resolved by their underlying `/N` component count) and composites an `/SMask`, if present,
    /// into the output image's alpha channel. This covers the common case for scanned-document
    /// PDFs as well as macOS screenshot-saved-as-PDF images, which are typically ICCBased with an
    /// alpha soft mask. CMYK, indexed palettes, and other bit depths remain unsupported.
    private static func decodeRawImage(data: Data, stream: CGPDFStreamRef) -> CGImage? {
        guard let dictionary = CGPDFStreamGetDictionary(stream) else { return nil }

        var width: CGPDFInteger = 0
        var height: CGPDFInteger = 0
        var bitsPerComponent: CGPDFInteger = 0
        guard
            CGPDFDictionaryGetInteger(dictionary, "Width", &width),
            CGPDFDictionaryGetInteger(dictionary, "Height", &height),
            CGPDFDictionaryGetInteger(dictionary, "BitsPerComponent", &bitsPerComponent),
            bitsPerComponent == 8
        else {
            return nil
        }

        guard let (colorSpace, componentsPerPixel) = resolveColorSpace(dictionary: dictionary, key: "ColorSpace") else {
            return nil
        }

        let bytesPerRow = Int(width) * componentsPerPixel
        guard data.count >= bytesPerRow * Int(height), let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        guard let baseImage = CGImage(
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bitsPerPixel: 8 * componentsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        var smaskStream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(dictionary, "SMask", &smaskStream), let smaskStream else {
            return baseImage
        }

        guard let maskImage = extractImage(from: smaskStream) else { return nil }
        return compositeAlphaMask(maskImage, onto: baseImage)
    }

    /// Resolves a PDF `/ColorSpace` entry to a `CGColorSpace` and its component count. Handles the
    /// literal device names as well as `[/ICCBased <stream>]` arrays, resolved via the stream
    /// dictionary's `/N` entry rather than by parsing the embedded ICC profile itself.
    private static func resolveColorSpace(dictionary: CGPDFDictionaryRef, key: String) -> (CGColorSpace, Int)? {
        var colorSpaceName: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(dictionary, key, &colorSpaceName), let colorSpaceName {
            return deviceColorSpace(named: String(cString: colorSpaceName))
        }

        var colorSpaceArray: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, key, &colorSpaceArray), let colorSpaceArray else {
            return nil
        }

        var familyName: UnsafePointer<CChar>?
        guard CGPDFArrayGetName(colorSpaceArray, 0, &familyName), let familyName else { return nil }

        switch String(cString: familyName) {
        case "ICCBased":
            var iccStream: CGPDFStreamRef?
            guard
                CGPDFArrayGetStream(colorSpaceArray, 1, &iccStream),
                let iccStream,
                let iccDictionary = CGPDFStreamGetDictionary(iccStream)
            else {
                return nil
            }

            var componentCount: CGPDFInteger = 0
            guard CGPDFDictionaryGetInteger(iccDictionary, "N", &componentCount) else { return nil }
            return deviceColorSpace(componentCount: Int(componentCount))

        default:
            return nil
        }
    }

    private static func deviceColorSpace(named name: String) -> (CGColorSpace, Int)? {
        switch name {
        case "DeviceGray":
            return (CGColorSpaceCreateDeviceGray(), 1)
        case "DeviceRGB":
            return (CGColorSpaceCreateDeviceRGB(), 3)
        default:
            return nil
        }
    }

    private static func deviceColorSpace(componentCount: Int) -> (CGColorSpace, Int)? {
        switch componentCount {
        case 1:
            return (CGColorSpaceCreateDeviceGray(), 1)
        case 3:
            return (CGColorSpaceCreateDeviceRGB(), 3)
        default:
            return nil
        }
    }

    /// Draws `baseImage` and `maskImage` (the resolved `/SMask`) into normalized RGBA/gray buffers
    /// of the same dimensions, then copies the mask's luminance into the base image's alpha
    /// channel. `CGContext.draw` handles any color-space conversion and mask rescaling needed.
    private static func compositeAlphaMask(_ maskImage: CGImage, onto baseImage: CGImage) -> CGImage? {
        let width = baseImage.width
        let height = baseImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var maskPixels = [UInt8](repeating: 0, count: width * height)
        guard let maskContext = CGContext(
            data: &maskPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        maskContext.draw(maskImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for pixelIndex in 0..<(width * height) {
            pixels[pixelIndex * bytesPerPixel + 3] = maskPixels[pixelIndex]
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * bytesPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func rebuildPDF(pages: [RecompressedPage]) -> Data? {
        guard var firstMediaBox = pages.first?.mediaBox else { return nil }

        let outputData = NSMutableData()
        guard
            let consumer = CGDataConsumer(data: outputData),
            let context = CGContext(consumer: consumer, mediaBox: &firstMediaBox, nil)
        else {
            return nil
        }

        for page in pages {
            var mediaBox = page.mediaBox
            let boxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
            let pageInfo = [kCGPDFContextMediaBox as String: boxData] as CFDictionary

            context.beginPDFPage(pageInfo)
            context.draw(page.image, in: CGRect(origin: .zero, size: page.mediaBox.size))
            context.endPDFPage()
        }

        context.closePDF()
        return outputData as Data
    }

    private static func encodePNG(from image: CGImage) throws -> Data {
        let targetData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(targetData, UTType.png.identifier as CFString, 1, nil) else {
            throw PNGOptimizerError.failedToCreateDestination
        }

        CGImageDestinationAddImage(destination, image, [:] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw PNGOptimizerError.failedToEncode
        }

        return targetData as Data
    }

    private static func optimizedOutputURL(for url: URL) -> URL {
        let baseName = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        return directory.appendingPathComponent("\(baseName)-optimized.pdf")
    }

    private struct QualifyingPage {
        let mediaBox: CGRect
        let stream: CGPDFStreamRef
    }

    private struct RecompressedPage {
        let mediaBox: CGRect
        let image: CGImage
    }
}
