import ComposableArchitecture
import CoreGraphics
import Foundation
import Testing
@testable import CompactBitmapPNG

@Suite("CompactBitmapPNG")
struct CompactBitmapPNGTests {
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

    @Test("Compression settings default to 256 colors, active")
    func pngQuantizationDefaults() {
        let settings = CompressionSettings()

        #expect(settings.quantizationLevel == .colors256)
        #expect(settings.overwriteOriginal == true)
    }

    @Test("App reducer processes discovered files with TCA")
    func appReducerProcessesDiscoveredFiles() async {
        let pngURL = URL(fileURLWithPath: "/tmp/sample.png")
        let pdfURL = URL(fileURLWithPath: "/tmp/sample.pdf")
        let pngResult = PNGCompressionResult(
            sourceURL: pngURL,
            outputURL: URL(fileURLWithPath: "/tmp/sample-optimized.png"),
            originalBytes: 1_000,
            compressedBytes: 700,
            status: .optimized,
            message: "Optimized successfully."
        )
        let pdfResult = PDFAnalysisResult(
            pdfURL: pdfURL,
            pageCount: 1,
            hasVectorContent: true,
            hasRasterImages: false,
            hasText: true,
            status: .vectorOnly,
            message: "This PDF contains vector/text content only."
        )

        let store = await MainActor.run {
            TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.processingClient.discoverSupportedFiles = { _ in
                    [
                        DiscoveredFile(url: pngURL, kind: .png),
                        DiscoveredFile(url: pdfURL, kind: .pdf)
                    ]
                }
                $0.processingClient.processPNGs = { _, _ in [pngResult] }
                $0.processingClient.processPDFs = { _ in [pdfResult] }
            }
        }

        await store.send(.processURLs([pngURL, pdfURL])) {
            $0.rootSelections = [pngURL, pdfURL]
        }
        await store.receive(.preparationFinished(
            IntakeSummary(
                acceptedPNGCount: 1,
                acceptedPDFCount: 1,
                skippedUnsupportedCount: 0,
                skippedDisabledCount: 0
            ),
            pngURLs: [pngURL],
            pdfURLs: [pdfURL]
        )) {
            $0.intakeMessage = "Queued 1 PNG and 1 PDF."
            $0.pendingPNGURLs = [pngURL]
            $0.pendingPDFURLs = [pdfURL]
            $0.processingState = .running("Compressing 1 PNG file and checking 1 PDF file...")
        }
        await store.receive(.processingFinished([pngResult], [pdfResult], [])) {
            $0.pngResults = [pngResult]
            $0.pdfResults = [pdfResult]
            $0.pendingPNGURLs = []
            $0.pendingPDFURLs = []
            $0.processingState = .idle
        }
    }

    @Test("App reducer runs PDF bitmap compression whenever PDF check is enabled")
    func appReducerCompressesPDFBitmapsWhenEnabled() async {
        let pdfURL = URL(fileURLWithPath: "/tmp/scan.pdf")
        let pdfResult = PDFAnalysisResult(
            pdfURL: pdfURL,
            pageCount: 1,
            hasVectorContent: false,
            hasRasterImages: true,
            hasText: false,
            status: .rasterOnly,
            message: "This PDF appears to be raster-image based only."
        )
        let compressionResult = PDFCompressionResult(
            sourceURL: pdfURL,
            outputURL: pdfURL,
            originalBytes: 1_000,
            compressedBytes: 400,
            status: .compressed,
            message: "Compressed embedded PDF bitmaps successfully."
        )

        let store = await MainActor.run {
            TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.processingClient.discoverSupportedFiles = { _ in
                    [DiscoveredFile(url: pdfURL, kind: .pdf)]
                }
                $0.processingClient.processPDFs = { _ in [pdfResult] }
                $0.processingClient.compressPDFBitmaps = { _, _ in [compressionResult] }
            }
        }

        await store.send(.processURLs([pdfURL])) {
            $0.rootSelections = [pdfURL]
        }
        await store.receive(.preparationFinished(
            IntakeSummary(
                acceptedPNGCount: 0,
                acceptedPDFCount: 1,
                skippedUnsupportedCount: 0,
                skippedDisabledCount: 0
            ),
            pngURLs: [],
            pdfURLs: [pdfURL]
        )) {
            $0.intakeMessage = "Queued 1 PDF."
            $0.pendingPDFURLs = [pdfURL]
            $0.processingState = .running("Checking 1 PDF file...")
        }
        await store.receive(.processingFinished([], [pdfResult], [compressionResult])) {
            $0.pdfResults = [pdfResult]
            $0.pdfCompressionResults = [compressionResult]
            $0.pendingPDFURLs = []
            $0.processingState = .idle
        }
    }

    @Test("App reducer shows an alert when a selection yields nothing to process")
    func appReducerShowsAlertWhenNothingProcessed() async {
        let unsupportedURL = URL(fileURLWithPath: "/tmp/notes.txt")

        let store = await MainActor.run {
            TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.processingClient.discoverSupportedFiles = { _ in
                    [DiscoveredFile(url: unsupportedURL, kind: nil)]
                }
            }
        }

        await store.send(.processURLs([unsupportedURL])) {
            $0.rootSelections = [unsupportedURL]
        }
        await store.receive(.preparationFinished(
            IntakeSummary(
                acceptedPNGCount: 0,
                acceptedPDFCount: 0,
                skippedUnsupportedCount: 1,
                skippedDisabledCount: 0
            ),
            pngURLs: [],
            pdfURLs: []
        )) {
            $0.intakeMessage = "No supported files were queued. Ignored 1 unsupported item."
            $0.processingState = .idle
            $0.alert = AlertState {
                TextState("Nothing to Process")
            } actions: {
                ButtonState(role: .cancel) {
                    TextState("OK")
                }
            } message: {
                TextState("No supported files were queued. Ignored 1 unsupported item.")
            }
        }
    }

    @Test("App reducer clears accumulated results")
    func appReducerClearsState() async {
        let store = await MainActor.run {
            TestStore(
                initialState: AppFeature.State(
                    processingState: .running("Working..."),
                    pngResults: [PNGCompressionResult(
                        sourceURL: URL(fileURLWithPath: "/tmp/source.png"),
                        outputURL: URL(fileURLWithPath: "/tmp/source-optimized.png"),
                        originalBytes: 100,
                        compressedBytes: 80,
                        status: .optimized,
                        message: "done"
                    )],
                    pdfResults: [PDFAnalysisResult(
                        pdfURL: URL(fileURLWithPath: "/tmp/file.pdf"),
                        pageCount: 1,
                        hasVectorContent: true,
                        hasRasterImages: false,
                        hasText: true,
                        status: .vectorOnly,
                        message: "done"
                    )],
                    enablePNGCompression: false,
                    enablePDFCheck: false,
                    compressionSettings: CompressionSettings(quantizationLevel: .colors64),
                    intakeMessage: "Custom",
                    rootSelections: [URL(fileURLWithPath: "/tmp")]
                )
            ) {
                AppFeature()
            }
        }

        await store.send(.clearResults) {
            $0 = AppFeature.State()
        }
    }

    @Test("App reducer cancels an in-progress run, keeping prior results and settings")
    func appReducerCancelsProcessing() async {
        let priorResult = PNGCompressionResult(
            sourceURL: URL(fileURLWithPath: "/tmp/done.png"),
            outputURL: URL(fileURLWithPath: "/tmp/done-optimized.png"),
            originalBytes: 100,
            compressedBytes: 80,
            status: .optimized,
            message: "done"
        )

        let store = await MainActor.run {
            TestStore(
                initialState: AppFeature.State(
                    processingState: .running("Compressing 1 PNG file..."),
                    pngResults: [priorResult],
                    pendingPNGURLs: [URL(fileURLWithPath: "/tmp/pending.png")],
                    enablePNGCompression: false,
                    enablePDFCheck: false,
                    compressionSettings: CompressionSettings(quantizationLevel: .colors64),
                    intakeMessage: "Queued 1 PNG.",
                    rootSelections: [URL(fileURLWithPath: "/tmp/pending.png")]
                )
            ) {
                AppFeature()
            }
        }

        await store.send(.cancelProcessing) {
            $0.processingState = .idle
            $0.pendingPNGURLs = []
            $0.intakeMessage = "Cancelled."
        }
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

    @Test("Adaptive quantization reduces a high-color image to the requested palette size")
    func adaptiveQuantizationReducesColorCount() throws {
        let image = try makeGradientImage(width: 24, height: 24)
        let quantizedCandidate = try PNGOptimizer.quantizedImage(from: image, maxColors: 16)
        let quantized = try #require(quantizedCandidate)
        let colors = try rgbaColors(in: quantized)

        #expect(colors.count <= 16)
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
