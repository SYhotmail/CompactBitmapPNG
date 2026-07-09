import Foundation
import Testing

@testable import CompactBitmapPNG

@Suite("PDF Vector Analyzer")
struct PDFVectorAnalyzerTests {
    @Test("A page that only paints an image is classified raster-only")
    func plainImagePageIsRasterOnly() throws {
        let image = PDFFixtureBuilder.rawImageObject(width: 10, height: 10)
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 10,
            mediaBoxHeight: 10,
            resources: "<< /XObject << /Im1 5 0 R >> >>",
            contentStream: "q 10 0 0 10 0 0 cm /Im1 Do Q",
            extraObjects: [image]
        )
        let url = try PDFFixtureBuilder.write(data, name: "plain-image")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFVectorAnalyzer.analyze(url: url)

        #expect(result.status == .rasterOnly)
        #expect(result.hasRasterImages == true)
        #expect(result.hasVectorContent == false)
    }

    @Test("An image wrapped in a clip-only rect (macOS Quartz screenshot boilerplate) is still raster-only, not mixed")
    func quartzClipWrappedImageIsRasterOnly() throws {
        // Regression test: this exact `re W n` clip-then-discard pattern is what every macOS
        // screenshot-saved-as-PDF wraps its single image in. Treating any path-construction
        // operator as "vector content" previously misclassified all such files as "mixed".
        let image = PDFFixtureBuilder.rawImageObject(width: 20, height: 20)
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 20,
            mediaBoxHeight: 20,
            resources: "<< /XObject << /Im1 5 0 R >> >>",
            contentStream: "q Q q 0 0 20 20 re W n /Perceptual ri q 20 0 0 20 0 0 cm /Im1 Do Q Q",
            extraObjects: [image]
        )
        let url = try PDFFixtureBuilder.write(data, name: "quartz-clip-wrapped")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFVectorAnalyzer.analyze(url: url)

        #expect(result.status == .rasterOnly)
        #expect(result.hasVectorContent == false)
        #expect(result.hasRasterImages == true)
    }

    @Test("A page that fills a rect is classified vector-only")
    func filledRectPageIsVectorOnly() throws {
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 50,
            mediaBoxHeight: 50,
            resources: "<< >>",
            contentStream: "1 0 0 rg 10 10 20 20 re f"
        )
        let url = try PDFFixtureBuilder.write(data, name: "filled-rect")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFVectorAnalyzer.analyze(url: url)

        #expect(result.status == .vectorOnly)
        #expect(result.hasVectorContent == true)
        #expect(result.hasRasterImages == false)
    }

    @Test("A page with both a filled rect and an image is classified mixed")
    func filledRectAndImagePageIsMixed() throws {
        let image = PDFFixtureBuilder.rawImageObject(width: 10, height: 10)
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 10,
            mediaBoxHeight: 10,
            resources: "<< /XObject << /Im1 5 0 R >> >>",
            contentStream: "1 0 0 rg 1 1 2 2 re f q 10 0 0 10 0 0 cm /Im1 Do Q",
            extraObjects: [image]
        )
        let url = try PDFFixtureBuilder.write(data, name: "filled-rect-and-image")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFVectorAnalyzer.analyze(url: url)

        #expect(result.status == .mixed)
        #expect(result.hasVectorContent == true)
        #expect(result.hasRasterImages == true)
    }

    @Test("A page with text is classified vector-only and reports text")
    func textOnlyPageReportsText() throws {
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 100,
            mediaBoxHeight: 100,
            resources: "<< >>",
            contentStream: "BT /F1 12 Tf 10 10 Td (Hello) Tj ET"
        )
        let url = try PDFFixtureBuilder.write(data, name: "text-only")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFVectorAnalyzer.analyze(url: url)

        #expect(result.status == .vectorOnly)
        #expect(result.hasText == true)
    }

    @Test("A page with no drawing operators reports no drawing data")
    func emptyPageReportsNoDrawingData() throws {
        let data = PDFFixtureBuilder.build(
            mediaBoxWidth: 10,
            mediaBoxHeight: 10,
            resources: "<< >>",
            contentStream: "q Q"
        )
        let url = try PDFFixtureBuilder.write(data, name: "empty-page")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFVectorAnalyzer.analyze(url: url)

        #expect(result.status == .noDrawingData)
        #expect(result.hasVectorContent == false)
        #expect(result.hasRasterImages == false)
    }
}
