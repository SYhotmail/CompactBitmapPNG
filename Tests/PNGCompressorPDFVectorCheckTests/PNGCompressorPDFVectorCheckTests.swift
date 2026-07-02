import Foundation
import Testing
@testable import PNGCompressorPDFVectorCheck

@Suite("PNG Compressor + PDF Vector Check")
struct PNGCompressorPDFVectorCheckTests {
    @Test("PNG savings are calculated when compression succeeds")
    func pngSavingsCalculation() {
        let result = PNGCompressionResult(
            sourceURL: URL(fileURLWithPath: "/tmp/source.png"),
            outputURL: URL(fileURLWithPath: "/tmp/source-optimized.png"),
            originalBytes: 1_000,
            compressedBytes: 700,
            status: .optimized,
            message: "Optimized successfully."
        )

        #expect(result.savingsBytes == 300)
        #expect(result.savingsPercent == 30)
        #expect(result.statusLabel == "Compressed")
    }

    @Test("PNG result without a smaller file reports no change")
    func pngUnchangedResult() {
        let result = PNGCompressionResult(
            sourceURL: URL(fileURLWithPath: "/tmp/source.png"),
            outputURL: nil,
            originalBytes: 1_000,
            compressedBytes: nil,
            status: .unchanged,
            message: "No smaller lossless version was produced."
        )

        #expect(result.savingsBytes == nil)
        #expect(result.savingsPercent == nil)
        #expect(result.statusLabel == "No Change")
    }

    @Test("PDF status labels match the detected content kind")
    func pdfStatusLabels() {
        let mixed = PDFAnalysisResult(
            pdfURL: URL(fileURLWithPath: "/tmp/mixed.pdf"),
            pageCount: 2,
            hasVectorContent: true,
            hasRasterImages: true,
            hasText: true,
            status: .mixed,
            message: "This PDF contains vector/text content and raster images."
        )

        let rasterOnly = PDFAnalysisResult(
            pdfURL: URL(fileURLWithPath: "/tmp/raster.pdf"),
            pageCount: 1,
            hasVectorContent: false,
            hasRasterImages: true,
            hasText: false,
            status: .rasterOnly,
            message: "This PDF appears to be raster-image based only."
        )

        #expect(mixed.statusLabel == "Vector + Raster")
        #expect(rasterOnly.statusLabel == "Raster Only")
    }

    @Test("Intake summary describes accepted, unsupported, and disabled files")
    func intakeSummaryDescription() {
        let summary = IntakeSummary(
            acceptedPNGCount: 2,
            acceptedPDFCount: 1,
            skippedUnsupportedCount: 3,
            skippedDisabledCount: 2
        )

        #expect(summary.description == "Queued 2 PNGs and 1 PDF. Ignored 3 unsupported items. Skipped 2 files because their operation is disabled.")
    }

    @Test("Intake summary handles empty queues cleanly")
    func emptyIntakeSummaryDescription() {
        let summary = IntakeSummary(
            acceptedPNGCount: 0,
            acceptedPDFCount: 0,
            skippedUnsupportedCount: 0,
            skippedDisabledCount: 0
        )

        #expect(summary.description == "No supported files were queued.")
    }
}
