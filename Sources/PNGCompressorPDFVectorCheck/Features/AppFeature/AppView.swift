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
            header
            settingsBar
            treeWindow
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 640)
        .alert($store.scope(state: \.alert, action: \.alert))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("app.title"))
                .font(.largeTitle.weight(.semibold))

            Text(headerSubtitle)
                .foregroundStyle(.secondary)
        }
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

    private var headerSubtitle: String {
        switch acceptedFileKinds {
        case .both: return L10n.string("header.subtitle.both")
        case .pngOnly: return L10n.string("header.subtitle.pngOnly")
        case .pdfOnly: return L10n.string("header.subtitle.pdfOnly")
        case .none: return L10n.string("header.subtitle.none")
        }
    }

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                Toggle(L10n.string("toggle.enablePngCompression"), isOn: $store.enablePNGCompression)
                    .accessibilityIdentifier("enable-png-compression-toggle")
                Toggle(L10n.string("toggle.enablePdfCheck"), isOn: $store.enablePDFCheck)
                    .accessibilityIdentifier("enable-pdf-check-toggle")
                Toggle(L10n.string("toggle.overwriteOriginal"), isOn: $store.pngCompressionSettings.overwriteOriginal)
                    .disabled(!store.enablePNGCompression)
                    .accessibilityIdentifier("overwrite-original-files-toggle")
            }
            .toggleStyle(.checkbox)

            if store.enablePNGCompression {
                HStack(spacing: 12) {
                    Text(L10n.string("quantization.sectionLabel"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    QuantizationLevelControl(selection: $store.pngCompressionSettings.quantizationLevel)
                        .accessibilityIdentifier("quantization-target-picker")

                    Spacer()
                }

                Text(store.pngCompressionSettings.quantizationLevel != nil
                     ? L10n.string("quantization.description.enabled")
                     : L10n.string("quantization.description.disabled"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("quantization-mode-description")
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            } else {
                Text(store.intakeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("intake-message-label")
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

/// A segmented-style control where tapping the already-selected segment deselects it,
/// which SwiftUI's built-in `Picker(selection:)` doesn't support since it always requires
/// a non-nil selection.
private struct QuantizationLevelControl: View {
    @Binding var selection: PNGQuantizationLevel?

    var body: some View {
        HStack(spacing: 1) {
            ForEach(PNGQuantizationLevel.allCases) { level in
                let isSelected = selection == level

                Button {
                    selection = isSelected ? nil : level
                } label: {
                    Text(level.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Color.accentColor : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(maxWidth: 280)
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
            return StatusPresentation(label: L10n.string("status.processing"), tint: .secondary, symbolName: nil, isPending: true, detail: "—")

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
            let detail = L10n.plural("pdf.pageCount", result.pageCount)

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

/// A node in the file/folder tree shown in the main window. Folder nodes carry a non-nil
/// (possibly empty) `children` array so SwiftUI's `List` draws a disclosure triangle; leaf
/// nodes carry `nil` so they render as plain rows.
private struct TreeNode: Identifiable {
    enum Content {
        case folder
        case file(FileRow)
    }

    let id: String
    let name: String
    let content: Content
    var children: [TreeNode]?

    var leafCount: Int {
        guard let children else { return 1 }
        return children.reduce(0) { $0 + $1.leafCount }
    }
}

/// Builds a tree from the raw top-level selections (what the user picked or dropped) and the
/// flat list of file rows discovered underneath them, nesting files by their path relative to
/// whichever selected folder contains them. Loose files selected directly become top-level leaves.
private func buildTree(rootSelections: [URL], fileRows: [FileRow]) -> [TreeNode] {
    var rowsByStandardizedURL: [URL: FileRow] = [:]
    for row in fileRows {
        rowsByStandardizedURL[row.id.standardizedFileURL] = row
    }

    var usedURLs: Set<URL> = []
    var nodes: [TreeNode] = []

    for root in rootSelections {
        let standardizedRoot = root.standardizedFileURL
        guard !usedURLs.contains(standardizedRoot) else { continue }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory)

        if exists, isDirectory.boolValue {
            let prefix = standardizedRoot.path + "/"
            let descendants = fileRows.filter { $0.id.standardizedFileURL.path.hasPrefix(prefix) }
            guard !descendants.isEmpty else { continue }

            usedURLs.formUnion(descendants.map { $0.id.standardizedFileURL })
            let children = buildChildren(prefix: standardizedRoot, rows: descendants)
            nodes.append(TreeNode(id: standardizedRoot.path, name: standardizedRoot.lastPathComponent, content: .folder, children: children))
        } else if let row = rowsByStandardizedURL[standardizedRoot] {
            usedURLs.insert(standardizedRoot)
            nodes.append(TreeNode(id: row.id.path, name: row.displayName, content: .file(row), children: nil))
        }
    }

    let orphaned = fileRows.filter { !usedURLs.contains($0.id.standardizedFileURL) }
    for row in orphaned.sorted(by: { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }) {
        nodes.append(TreeNode(id: row.id.path, name: row.displayName, content: .file(row), children: nil))
    }

    return nodes
}

private func buildChildren(prefix: URL, rows: [FileRow]) -> [TreeNode] {
    var directFiles: [FileRow] = []
    var groupedByFolder: [String: [FileRow]] = [:]
    var folderOrder: [String] = []

    let prefixPath = prefix.path
    for row in rows {
        let fullPath = row.id.standardizedFileURL.path
        let relative = fullPath.hasPrefix(prefixPath + "/") ? String(fullPath.dropFirst(prefixPath.count + 1)) : fullPath
        let components = relative.split(separator: "/")
        guard let first = components.first else { continue }

        if components.count == 1 {
            directFiles.append(row)
        } else {
            let key = String(first)
            if groupedByFolder[key] == nil { folderOrder.append(key) }
            groupedByFolder[key, default: []].append(row)
        }
    }

    var nodes: [TreeNode] = directFiles
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        .map { TreeNode(id: $0.id.path, name: $0.displayName, content: .file($0), children: nil) }

    for key in folderOrder.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
        let childPrefix = prefix.appendingPathComponent(key)
        let children = buildChildren(prefix: childPrefix, rows: groupedByFolder[key] ?? [])
        nodes.append(TreeNode(id: childPrefix.path, name: key, content: .folder, children: children))
    }

    return nodes
}

/// Renders a tree node, recursing into a `DisclosureGroup` for folders. Expansion state is
/// keyed by the node's stable path `id` and defaults to expanded, so newly discovered folders
/// (from a fresh selection or drop) show their contents immediately instead of collapsed.
private struct TreeNodeView: View {
    let node: TreeNode
    @Binding var collapsedFolderIDs: Set<String>

    var body: some View {
        switch node.content {
        case .folder:
            DisclosureGroup(isExpanded: isExpandedBinding) {
                ForEach(node.children ?? []) { child in
                    TreeNodeView(node: child, collapsedFolderIDs: $collapsedFolderIDs)
                }
            } label: {
                TreeNodeRowView(node: node)
            }

        case .file:
            TreeNodeRowView(node: node)
        }
    }

    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: { !collapsedFolderIDs.contains(node.id) },
            set: { isExpanded in
                if isExpanded {
                    collapsedFolderIDs.remove(node.id)
                } else {
                    collapsedFolderIDs.insert(node.id)
                }
            }
        )
    }
}

private struct TreeNodeRowView: View {
    let node: TreeNode

    var body: some View {
        switch node.content {
        case .folder:
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)

                Text(node.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(L10n.plural("files.itemCount", node.leafCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("tree-folder-\(node.name)")

        case let .file(row):
            let presentation = row.statusPresentation

            HStack(spacing: 10) {
                Image(systemName: row.kindIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(row.displayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(row.kindLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

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
                .frame(width: 130, alignment: .leading)

                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 100, maxWidth: 220, alignment: .leading)
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("file-row-\(row.displayName)")
        }
    }
}
