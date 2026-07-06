import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: StoreOf<AppFeature>
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controlPanel
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

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Toggle("Enable PNG compression", isOn: $store.enablePNGCompression)
                    .accessibilityIdentifier("enable-png-compression-toggle")
                Toggle("Enable PDF check", isOn: $store.enablePDFCheck)
                    .accessibilityIdentifier("enable-pdf-check-toggle")
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable lossy PNG quantization", isOn: $store.pngCompressionSettings.enableAdaptiveQuantization)
                    .toggleStyle(.switch)
                    .disabled(!store.enablePNGCompression)
                    .accessibilityIdentifier("enable-lossy-quantization-toggle")

                if store.pngCompressionSettings.enableAdaptiveQuantization {
                    HStack(spacing: 12) {
                        Text("Quantization target")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Quantization target", selection: $store.pngCompressionSettings.quantizationLevel) {
                            ForEach(PNGQuantizationLevel.allCases) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                        .accessibilityIdentifier("quantization-target-picker")
                    }
                }

                Text(store.pngCompressionSettings.enableAdaptiveQuantization
                     ? "Lossless PNG optimization will run first, then the selected lossy quantization level will be tried and only kept if it makes the file smaller."
                     : "Only lossless PNG optimization will run. Quantization is off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("quantization-mode-description")
            }

            HStack(spacing: 12) {
                Button("Choose Files", action: chooseFiles)
                    .accessibilityIdentifier("choose-files-button")
                Button("Choose Folder", action: chooseFolder)
                    .accessibilityIdentifier("choose-folder-button")
                Button("Clear Results") {
                    store.send(.clearResults)
                }
                .accessibilityIdentifier("clear-results-button")
            }

            if let folderPath = store.selectedFolderPath {
                Text("Selected folder: \(folderPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("selected-folder-label")
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

            if case let .running(message) = store.processingState {
                ProgressView(message)
                    .padding(.top, 6)
                    .accessibilityIdentifier("processing-progress-view")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180)
        .background(dropZoneBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
        )
        .accessibilityIdentifier("drop-zone")
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            processDroppedItems(providers)
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

            Text(store.intakeMessage)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("intake-message-label")

            HStack(spacing: 16) {
                statusPill(title: "PNG Results", count: store.pngResults.count, tint: .green)
                statusPill(title: "PDF Results", count: store.pdfResults.count, tint: .blue)
            }
        }
    }

    private var pngResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PNG Compression")
                .font(.title3.weight(.semibold))

            if store.pngResults.isEmpty {
                EmptyStateView(
                    title: "No PNG Status Yet",
                    systemImage: "photo",
                    message: "Enable PNG compression and choose files, a folder, or drop PNGs here."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.pngResults) { result in
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

            if store.pdfResults.isEmpty {
                EmptyStateView(
                    title: "No PDF Status Yet",
                    systemImage: "doc.text.image",
                    message: "Enable PDF check and choose files, a folder, or drop PDFs here."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.pdfResults) { result in
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

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        store.send(.processURLs(panel.urls, sourceFolderPath: nil))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        store.send(.processURLs([folderURL], sourceFolderPath: folderURL.path))
    }

    private func processDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !supported.isEmpty else { return false }

        Task {
            let urls = await loadURLs(from: supported)
            guard !urls.isEmpty else { return }
            store.send(.processURLs(urls, sourceFolderPath: nil))
        }

        return true
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
