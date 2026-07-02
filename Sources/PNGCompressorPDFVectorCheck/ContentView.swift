import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class AppViewModel {
    private let pipeline = ProcessingPipeline()
    private var processingTask: Task<Void, Never>?

    var processingState: ProcessingState = .idle
    var pngResults: [PNGCompressionResult] = []
    var pdfResults: [PDFAnalysisResult] = []
    var enablePNGCompression = true
    var enablePDFCheck = true
    var intakeMessage = "Drop PNG or PDF files here, or choose files or a folder to process."
    var selectedFolderPath: String?

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        startProcessing(panel.urls, sourceFolderPath: nil)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        selectedFolderPath = folderURL.path
        startProcessing([folderURL], sourceFolderPath: folderURL.path)
    }

    func processDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !supported.isEmpty else { return false }

        Task {
            let urls = await loadURLs(from: supported)
            guard !urls.isEmpty else { return }
            await processInputs(urls, sourceFolderPath: nil)
        }

        return true
    }

    func clearResults() {
        processingTask?.cancel()
        pngResults = []
        pdfResults = []
        processingState = .idle
        selectedFolderPath = nil
        intakeMessage = "Drop PNG or PDF files here, or choose files or a folder to process."
    }

    private func startProcessing(_ urls: [URL], sourceFolderPath: String?) {
        processingTask?.cancel()
        processingTask = Task {
            await processInputs(urls, sourceFolderPath: sourceFolderPath)
        }
    }

    private func processInputs(_ urls: [URL], sourceFolderPath: String?) async {
        let discovered = await pipeline.discoverSupportedFiles(from: urls)
        let summary = summarize(files: discovered)
        intakeMessage = summary.description
        selectedFolderPath = sourceFolderPath

        let pngURLs = enablePNGCompression ? discovered.compactMap { $0.kind == .png ? $0.url : nil } : []
        let pdfURLs = enablePDFCheck ? discovered.compactMap { $0.kind == .pdf ? $0.url : nil } : []

        guard !Task.isCancelled else { return }

        guard !pngURLs.isEmpty || !pdfURLs.isEmpty else {
            processingState = .idle
            return
        }

        processingState = .running(statusMessage(pngCount: pngURLs.count, pdfCount: pdfURLs.count))

        async let pngTask = pipeline.processPNGs(urls: pngURLs)
        async let pdfTask = pipeline.processPDFs(urls: pdfURLs)
        let (pngResults, pdfResults) = await (pngTask, pdfTask)

        guard !Task.isCancelled else { return }

        self.pngResults = pngResults
        self.pdfResults = pdfResults
        self.processingState = .idle
    }

    private func summarize(files: [DiscoveredFile]) -> IntakeSummary {
        let pngCount = files.filter { $0.kind == .png }.count
        let pdfCount = files.filter { $0.kind == .pdf }.count
        let unsupportedCount = files.filter { $0.kind == nil }.count

        let disabledCount =
            (enablePNGCompression ? 0 : pngCount) +
            (enablePDFCheck ? 0 : pdfCount)

        return IntakeSummary(
            acceptedPNGCount: enablePNGCompression ? pngCount : 0,
            acceptedPDFCount: enablePDFCheck ? pdfCount : 0,
            skippedUnsupportedCount: unsupportedCount,
            skippedDisabledCount: disabledCount
        )
    }

    private func statusMessage(pngCount: Int, pdfCount: Int) -> String {
        if pngCount > 0 && pdfCount > 0 {
            return "Compressing \(pngCount) PNG file(s) and checking \(pdfCount) PDF file(s)..."
        }

        if pngCount > 0 {
            return "Compressing \(pngCount) PNG file(s)..."
        }

        return "Checking \(pdfCount) PDF file(s)..."
    }

    private func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadURL(from: provider) {
                urls.append(url)
            }
        }

        return urls
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard
                    let data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: url)
            }
        }
    }

}

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controlPanel(
                    viewModel: viewModel,
                    enablePNGCompression: $bindableViewModel.enablePNGCompression,
                    enablePDFCheck: $bindableViewModel.enablePDFCheck
                )
                dropZone
                resultsSummary
                pngResultsSection
                pdfResultsSection
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PNG Compressor + PDF Vector Check")
                .font(.largeTitle.weight(.semibold))

            Text("Drop files or point the app at a folder, then choose whether to compress PNGs, check PDFs for raster data, or run both.")
                .foregroundStyle(.secondary)
        }
    }

    private func controlPanel(
        viewModel: AppViewModel,
        enablePNGCompression: Binding<Bool>,
        enablePDFCheck: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Toggle("Enable PNG compression", isOn: enablePNGCompression)
                Toggle("Enable PDF check", isOn: enablePDFCheck)
            }
            .toggleStyle(.switch)

            HStack(spacing: 12) {
                Button("Choose Files", action: viewModel.chooseFiles)
                Button("Choose Folder", action: viewModel.chooseFolder)
                Button("Clear Results", action: viewModel.clearResults)
            }

            if let folderPath = viewModel.selectedFolderPath {
                Text("Selected folder: \(folderPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 34))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

            Text("Drag PNG or PDF files here")
                .font(.headline)

            Text("Folders are supported too. The app will scan them for `.png` and `.pdf` files.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if case let .running(message) = viewModel.processingState {
                ProgressView(message)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180)
        .background(dropZoneBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            viewModel.processDroppedItems(providers)
        }
    }

    private var dropZoneBackground: some ShapeStyle {
        LinearGradient(
            colors: isDropTargeted
                ? [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.06)]
                : [Color.gray.opacity(0.12), Color.gray.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var resultsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.title3.weight(.semibold))

            Text(viewModel.intakeMessage)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statusPill(title: "PNG Results", count: viewModel.pngResults.count, tint: .green)
                statusPill(title: "PDF Results", count: viewModel.pdfResults.count, tint: .blue)
            }
        }
    }

    private var pngResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PNG Compression")
                .font(.title3.weight(.semibold))

            if viewModel.pngResults.isEmpty {
                EmptyStateView(
                    title: "No PNG Status Yet",
                    systemImage: "photo",
                    message: "Enable PNG compression and choose files, a folder, or drop PNGs here."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.pngResults) { result in
                        ResultCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(result.sourceURL.lastPathComponent)
                                        .font(.headline)
                                    Spacer()
                                    BadgeView(text: result.statusLabel, tint: result.status == .failed ? .red : (result.status == .optimized ? .green : .orange))
                                }

                                Text(result.message)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 14) {
                                    Text("Original: \(byteCountDescription(result.originalBytes))")

                                    if let compressedBytes = result.compressedBytes {
                                        Text("Compressed: \(byteCountDescription(compressedBytes))")
                                    }

                                    if let savingsBytes = result.savingsBytes,
                                       let savingsPercent = result.savingsPercent {
                                        Text("Saved: \(byteCountDescription(savingsBytes)) (\(savingsPercent.formatted(.number.precision(.fractionLength(1))))%)")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .font(.caption)

                                if let outputURL = result.outputURL {
                                    Text(outputURL.path)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var pdfResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PDF Check")
                .font(.title3.weight(.semibold))

            if viewModel.pdfResults.isEmpty {
                EmptyStateView(
                    title: "No PDF Status Yet",
                    systemImage: "doc.text.image",
                    message: "Enable PDF check and choose files, a folder, or drop PDFs here."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.pdfResults) { result in
                        ResultCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(result.pdfURL.lastPathComponent)
                                        .font(.headline)
                                    Spacer()
                                    BadgeView(text: result.statusLabel, tint: pdfTint(for: result.status))
                                }

                                Text(result.message)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 14) {
                                    Text("Pages: \(result.pageCount)")
                                    Text(result.hasVectorContent ? "Vector/Text: Yes" : "Vector/Text: No")
                                    Text(result.hasRasterImages ? "Raster Data: Yes" : "Raster Data: No")
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusPill(title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text("\(title): \(count)")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func pdfTint(for status: PDFContentStatus) -> Color {
        switch status {
        case .mixed:
            return .blue
        case .vectorOnly:
            return .green
        case .rasterOnly:
            return .orange
        case .noDrawingData:
            return .gray
        case .failed:
            return .red
        }
    }
}

private struct ResultCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }
}

private struct BadgeView: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
