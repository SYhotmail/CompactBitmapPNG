import ComposableArchitecture
import Foundation

struct ProcessingClient: Sendable {
    var discoverSupportedFiles: @Sendable ([URL]) async -> [DiscoveredFile]
    var processPNGs: @Sendable ([URL], CompressionSettings) async -> [PNGCompressionResult]
    var processPDFs: @Sendable ([URL]) async -> [PDFAnalysisResult]
    var compressPDFBitmaps: @Sendable ([URL], CompressionSettings) async -> [PDFCompressionResult]
}

private enum ProcessingClientKey: DependencyKey {
    static let liveValue: ProcessingClient = {
        let pipeline = ProcessingPipeline()
        return ProcessingClient(
            discoverSupportedFiles: { urls in
                await pipeline.discoverSupportedFiles(from: urls)
            },
            processPNGs: { urls, settings in
                await pipeline.processPNGs(urls: urls, settings: settings)
            },
            processPDFs: { urls in
                await pipeline.processPDFs(urls: urls)
            },
            compressPDFBitmaps: { urls, settings in
                await pipeline.compressPDFBitmaps(urls: urls, settings: settings)
            }
        )
    }()

    static let testValue = ProcessingClient(
        discoverSupportedFiles: { _ in [] },
        processPNGs: { _, _ in [] },
        processPDFs: { _ in [] },
        compressPDFBitmaps: { _, _ in [] }
    )
}

extension DependencyValues {
    var processingClient: ProcessingClient {
        get { self[ProcessingClientKey.self] }
        set { self[ProcessingClientKey.self] = newValue }
    }
}
