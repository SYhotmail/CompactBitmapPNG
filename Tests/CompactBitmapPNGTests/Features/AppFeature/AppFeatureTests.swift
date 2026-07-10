@testable import CompactBitmapPNG
import ComposableArchitecture
import Foundation
import Testing

@Suite("AppFeature reducer")
struct AppFeatureTests {
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
}
