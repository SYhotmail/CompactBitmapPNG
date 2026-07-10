import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @State private var isDropTargeted = false
    @State private var collapsedFolderIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsBar
            treeWindow
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 640)
        .alert($store.scope(state: \.alert, action: \.alert))
    }

    /// Which file kinds are currently eligible for processing, per the two toggles. Drives all
    /// the "what will this app accept" copy so it stays truthful as the toggles change.
    private enum AcceptedFileKinds {
        case none
        case pngOnly
        case pdfOnly
        case both
    }

    private var acceptedFileKinds: AcceptedFileKinds {
        switch (store.enablePNGCompression, store.enablePDFCheck) {
        case (true, true): return .both
        case (true, false): return .pngOnly
        case (false, true): return .pdfOnly
        case (false, false): return .none
        }
    }

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("compression.sectionLabel"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                Toggle(L10n.string("toggle.enablePngCompression"), isOn: $store.enablePNGCompression)
                    .accessibilityIdentifier("enable-png-compression-toggle")
                Toggle(L10n.string("toggle.enablePdfCheck"), isOn: $store.enablePDFCheck)
                    .accessibilityIdentifier("enable-pdf-check-toggle")
                Toggle(L10n.string("toggle.overwriteOriginal"), isOn: $store.compressionSettings.overwriteOriginal)
                    .accessibilityIdentifier("overwrite-original-files-toggle")
            }
            .toggleStyle(.checkbox)

            if store.enablePNGCompression || store.enablePDFCheck {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(L10n.string("quantization.sectionLabel"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        QuantizationLevelControl(selection: $store.compressionSettings.quantizationLevel)
                            .accessibilityIdentifier("quantization-target-picker")
                    }

                    Text(
                        store.compressionSettings.quantizationLevel != nil
                            ? L10n.string("quantization.description.enabled")
                            : L10n.string("quantization.description.disabled")
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("quantization-mode-description")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    private var treeNodes: [TreeNode] {
        buildTree(rootSelections: store.rootSelections, fileRows: fileRows)
    }

    private var treeWindow: some View {
        VStack(alignment: .leading, spacing: 0) {
            treeWindowHeader
            Divider()

            Group {
                if fileRows.isEmpty {
                    emptyDropState
                } else {
                    List {
                        ForEach(treeNodes) { node in
                            TreeNodeView(node: node, collapsedFolderIDs: $collapsedFolderIDs)
                        }
                    }
                    .listStyle(.inset)
                    .accessibilityIdentifier("file-tree")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: fileRows.isEmpty ? [8] : [])
                )
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            processDroppedItems(providers)
        }
    }

    private var treeWindowHeader: some View {
        HStack(spacing: 10) {
            Button(action: selectFilesOrFolder) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)

                    Text(L10n.string("files.title"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .help(L10n.string("files.selectHelp"))
            .accessibilityIdentifier("files-header-select-button")

            Spacer()

            Text(L10n.plural("files.itemCount", fileRows.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("file-list-item-count")

            Button {
                store.send(.clearResults)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.string("files.clearHelp"))
            .accessibilityIdentifier("clear-results-button")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyDropStateTitle: String {
        switch acceptedFileKinds {
        case .both: return L10n.string("emptyState.title.both")
        case .pngOnly: return L10n.string("emptyState.title.pngOnly")
        case .pdfOnly: return L10n.string("emptyState.title.pdfOnly")
        case .none: return L10n.string("emptyState.title.none")
        }
    }

    private var emptyDropStateSubtitle: String {
        switch acceptedFileKinds {
        case .both: return L10n.string("emptyState.subtitle.both")
        case .pngOnly: return L10n.string("emptyState.subtitle.pngOnly")
        case .pdfOnly: return L10n.string("emptyState.subtitle.pdfOnly")
        case .none: return L10n.string("emptyState.subtitle.none")
        }
    }

    private var emptyDropState: some View {
        Button(action: selectFilesOrFolder) {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 34))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

                Text(emptyDropStateTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(emptyDropStateSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("empty-drop-state-select-button")
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if case let .running(message) = store.processingState {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("processing-progress-view")
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    store.send(.cancelProcessing)
                } label: {
                    Text(L10n.string("processing.cancel"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(L10n.string("processing.cancelHelp"))
                .accessibilityIdentifier("cancel-processing-button")
            } else {
                Text(store.intakeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("intake-message-label")

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var fileRows: [FileRow] {
        let compressionResultsByURL = Dictionary(uniqueKeysWithValues: store.pdfCompressionResults.map { ($0.sourceURL, $0) })

        var rows: [FileRow] = []
        rows.append(contentsOf: store.pendingPNGURLs.map { FileRow(id: $0, kind: .png, status: .pending) })
        rows.append(contentsOf: store.pendingPDFURLs.map { FileRow(id: $0, kind: .pdf, status: .pending) })
        rows.append(contentsOf: store.pngResults.map { FileRow(id: $0.sourceURL, kind: .png, status: .png($0)) })
        rows.append(contentsOf: store.pdfResults.map {
            FileRow(id: $0.pdfURL, kind: .pdf, status: .pdf($0, compressionResultsByURL[$0.pdfURL]))
        })

        return rows.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func selectFilesOrFolder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }
        store.send(.processURLs(panel.urls))
    }

    private func processDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !supported.isEmpty else { return false }

        Task {
            let urls = await loadURLs(from: supported)
            guard !urls.isEmpty else { return }
            store.send(.processURLs(urls))
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
