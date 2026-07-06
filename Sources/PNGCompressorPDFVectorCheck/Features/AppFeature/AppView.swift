import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controlPanel
                dropZone
                fileListSection
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

    private var fileRows: [FileRow] {
        var rows: [FileRow] = []
        rows.append(contentsOf: store.pendingPNGURLs.map { FileRow(id: $0, kind: .png, status: .pending) })
        rows.append(contentsOf: store.pendingPDFURLs.map { FileRow(id: $0, kind: .pdf, status: .pending) })
        rows.append(contentsOf: store.pngResults.map { FileRow(id: $0.sourceURL, kind: .png, status: .png($0)) })
        rows.append(contentsOf: store.pdfResults.map { FileRow(id: $0.pdfURL, kind: .pdf, status: .pdf($0)) })

        return rows.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var folderTitle: String {
        if let path = store.selectedFolderPath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "Dropped Files"
    }

    private var fileListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)

                Text(folderTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(fileRows.count) item\(fileRows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("file-list-item-count")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Text(store.intakeMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("intake-message-label")

            if fileRows.isEmpty {
                EmptyStateView(
                    title: "No Files Yet",
                    systemImage: "folder",
                    message: "Choose files or a folder, or drop PNGs and PDFs above to see their status here."
                )
                .padding(16)
            } else {
                Divider()
                fileListHeader
                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(fileRows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Divider().opacity(0.5)
                            }
                            FileRowView(row: row, isAlternate: !index.isMultiple(of: 2))
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: 440)
                .accessibilityIdentifier("file-results-list")
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var fileListHeader: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 20)
            Text("Name").frame(minWidth: 160, alignment: .leading)
            Text("Kind").frame(width: 40, alignment: .leading)
            Text("Status").frame(width: 150, alignment: .leading)
            Text("Details").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.3))
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

private struct FileRow: Identifiable {
    enum Kind {
        case png
        case pdf
    }

    enum Status {
        case pending
        case png(PNGCompressionResult)
        case pdf(PDFAnalysisResult)
    }

    let id: URL
    let kind: Kind
    let status: Status

    var displayName: String { id.lastPathComponent }

    var kindLabel: String {
        switch kind {
        case .png: return "PNG"
        case .pdf: return "PDF"
        }
    }

    var kindIcon: String {
        switch kind {
        case .png: return "photo"
        case .pdf: return "doc.text.image"
        }
    }

    var statusPresentation: StatusPresentation {
        switch status {
        case .pending:
            return StatusPresentation(label: "Processing…", tint: .secondary, symbolName: nil, isPending: true, detail: "—")

        case let .png(result):
            switch result.status {
            case .optimized:
                let detail: String
                if let compressedBytes = result.compressedBytes, let percent = result.savingsPercent {
                    detail = "\(byteCountDescription(result.originalBytes)) → \(byteCountDescription(compressedBytes)) (-\(percent.formatted(.number.precision(.fractionLength(1))))%)"
                } else {
                    detail = result.message
                }
                return StatusPresentation(label: result.statusLabel, tint: .green, symbolName: "checkmark.circle.fill", isPending: false, detail: detail)

            case .unchanged:
                return StatusPresentation(label: result.statusLabel, tint: .orange, symbolName: "minus.circle.fill", isPending: false, detail: byteCountDescription(result.originalBytes))

            case .failed:
                return StatusPresentation(label: result.statusLabel, tint: .red, symbolName: "xmark.circle.fill", isPending: false, detail: result.message)
            }

        case let .pdf(result):
            let detail = "\(result.pageCount) page\(result.pageCount == 1 ? "" : "s")"

            switch result.status {
            case .mixed:
                return StatusPresentation(label: result.statusLabel, tint: .blue, symbolName: "circle.lefthalf.filled", isPending: false, detail: detail)
            case .vectorOnly:
                return StatusPresentation(label: result.statusLabel, tint: .green, symbolName: "checkmark.circle.fill", isPending: false, detail: detail)
            case .rasterOnly:
                return StatusPresentation(label: result.statusLabel, tint: .orange, symbolName: "photo.circle.fill", isPending: false, detail: detail)
            case .noDrawingData:
                return StatusPresentation(label: result.statusLabel, tint: .gray, symbolName: "questionmark.circle.fill", isPending: false, detail: detail)
            case .failed:
                return StatusPresentation(label: result.statusLabel, tint: .red, symbolName: "xmark.circle.fill", isPending: false, detail: result.message)
            }
        }
    }
}

private struct StatusPresentation {
    let label: String
    let tint: Color
    let symbolName: String?
    let isPending: Bool
    let detail: String
}

private struct FileRowView: View {
    let row: FileRow
    let isAlternate: Bool

    var body: some View {
        let presentation = row.statusPresentation

        HStack(spacing: 12) {
            Image(systemName: row.kindIcon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(row.displayName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 160, alignment: .leading)

            Text(row.kindLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            HStack(spacing: 6) {
                if presentation.isPending {
                    ProgressView()
                        .controlSize(.small)
                } else if let symbolName = presentation.symbolName {
                    Image(systemName: symbolName)
                        .foregroundStyle(presentation.tint)
                }

                Text(presentation.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(presentation.tint)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            Text(presentation.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isAlternate ? Color.gray.opacity(0.06) : Color.clear)
        .accessibilityIdentifier("file-row-\(row.displayName)")
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
