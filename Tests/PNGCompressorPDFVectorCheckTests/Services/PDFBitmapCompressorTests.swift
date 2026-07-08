import Foundation
import Testing

@testable import PNGCompressorPDFVectorCheck

@Suite("PDF Bitmap Compressor")
struct PDFBitmapCompressorTests {
    @Test("A single raw solid-color image page is recompressed smaller")
    func compressesSingleImagePage() throws {
        // Wrapped in the same clip-then-discard boilerplate real macOS screenshot PDFs use, so
        // this also doubles as coverage that the compressor sees through it like the analyzer does.
        let image = PDFFixtureBuilder.rawImageObject(width: 200, height: 200)
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 200,
            mediaBoxHeight: 200,
            resources: "<< /XObject << /Im1 5 0 R >> >>",
            contentStream: "q Q q 0 0 200 200 re W n /Perceptual ri q 200 0 0 200 0 0 cm /Im1 Do Q Q",
            extraObjects: [image]
        )
        let url = try PDFFixtureBuilder.write(data, name: "solid-color")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFBitmapCompressor.compress(
            url: url,
            settings: CompressionSettings(quantizationLevel: .colors64, overwriteOriginal: false)
        )

        #expect(result.status == .compressed)
        let outputURL = try #require(result.outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let compressedBytes = try #require(result.compressedBytes)
        #expect(compressedBytes < result.originalBytes)
    }

    @Test("A page with visible vector content alongside its image is left unchanged")
    func leavesMixedContentPageUnchanged() throws {
        let image = PDFFixtureBuilder.rawImageObject(width: 50, height: 50)
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 50,
            mediaBoxHeight: 50,
            resources: "<< /XObject << /Im1 5 0 R >> >>",
            contentStream: "1 0 0 rg 1 1 2 2 re f q 50 0 0 50 0 0 cm /Im1 Do Q",
            extraObjects: [image]
        )
        let url = try PDFFixtureBuilder.write(data, name: "mixed-content")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFBitmapCompressor.compress(url: url, settings: CompressionSettings())

        #expect(result.status == .unchanged)
        #expect(result.outputURL == nil)
    }

    @Test("A page with two images is left unchanged (not a single dominant image)")
    func leavesMultiImagePageUnchanged() throws {
        let imageA = PDFFixtureBuilder.rawImageObject(width: 20, height: 20)
        let imageB = PDFFixtureBuilder.rawImageObject(width: 20, height: 20, pixel: [10, 200, 60])
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 40,
            mediaBoxHeight: 20,
            resources: "<< /XObject << /Im1 5 0 R /Im2 6 0 R >> >>",
            contentStream: "q 20 0 0 20 0 0 cm /Im1 Do Q q 20 0 0 20 20 0 cm /Im2 Do Q",
            extraObjects: [imageA, imageB]
        )
        let url = try PDFFixtureBuilder.write(data, name: "two-images")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFBitmapCompressor.compress(url: url, settings: CompressionSettings())

        #expect(result.status == .unchanged)
        #expect(result.outputURL == nil)
    }

    @Test("A CMYK image is left unchanged (unsupported color format)")
    func leavesCMYKImageUnchanged() throws {
        let image = PDFFixtureBuilder.rawImageObject(
            width: 10,
            height: 10,
            colorSpace: "/DeviceCMYK",
            componentsPerPixel: 4,
            pixel: [0, 0, 0, 100]
        )
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 10,
            mediaBoxHeight: 10,
            resources: "<< /XObject << /Im1 5 0 R >> >>",
            contentStream: "q 10 0 0 10 0 0 cm /Im1 Do Q",
            extraObjects: [image]
        )
        let url = try PDFFixtureBuilder.write(data, name: "cmyk-image")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFBitmapCompressor.compress(url: url, settings: CompressionSettings())

        #expect(result.status == .unchanged)
        #expect(result.outputURL == nil)
    }

    @Test("An image with a soft mask is composited and recompressed")
    func compositesSoftMaskedImage() throws {
        let mask = PDFFixtureBuilder.rawGrayMaskObject(width: 200, height: 200, value: 128)
        let image = PDFFixtureBuilder.rawImageObject(width: 200, height: 200, smaskObjectNumber: 6)
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 200,
            mediaBoxHeight: 200,
            resources: "<< /XObject << /Im1 5 0 R >> >>",
            contentStream: "q 200 0 0 200 0 0 cm /Im1 Do Q",
            extraObjects: [image, mask]
        )
        let url = try PDFFixtureBuilder.write(data, name: "soft-masked-image")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFBitmapCompressor.compress(url: url, settings: CompressionSettings())

        #expect(result.status == .compressed)
        let outputURL = try #require(result.outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let compressedBytes = try #require(result.compressedBytes)
        #expect(compressedBytes < result.originalBytes)
    }

    @Test("An ICCBased color space is resolved via its /N component count")
    func resolvesICCBasedColorSpace() throws {
        let iccProfile = PDFFixtureBuilder.iccBasedColorSpaceObject(componentsPerPixel: 3)
        let image = PDFFixtureBuilder.rawImageObject(width: 200, height: 200, colorSpace: "[/ICCBased 6 0 R]")
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 200,
            mediaBoxHeight: 200,
            resources: "<< /XObject << /Im1 5 0 R >> >>",
            contentStream: "q 200 0 0 200 0 0 cm /Im1 Do Q",
            extraObjects: [image, iccProfile]
        )
        let url = try PDFFixtureBuilder.write(data, name: "icc-based-image")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFBitmapCompressor.compress(url: url, settings: CompressionSettings())

        #expect(result.status == .compressed)
        let outputURL = try #require(result.outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test("An ICCBased + SMask image (typical macOS screenshot PDF shape) is recompressed")
    func compressesICCBasedImageWithSoftMask() throws {
        let iccProfile = PDFFixtureBuilder.iccBasedColorSpaceObject(componentsPerPixel: 3)
        let mask = PDFFixtureBuilder.rawGrayMaskObject(width: 200, height: 200, value: 200)
        let image = PDFFixtureBuilder.rawImageObject(
            width: 200,
            height: 200,
            colorSpace: "[/ICCBased 7 0 R]",
            smaskObjectNumber: 6
        )
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 200,
            mediaBoxHeight: 200,
            resources: "<< /XObject << /Im1 5 0 R >> >>",
            contentStream: "q 200 0 0 200 0 0 cm /Im1 Do Q",
            extraObjects: [image, mask, iccProfile]
        )
        let url = try PDFFixtureBuilder.write(data, name: "screenshot-shaped-image")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFBitmapCompressor.compress(url: url, settings: CompressionSettings())

        #expect(result.status == .compressed)
        let outputURL = try #require(result.outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }
}
