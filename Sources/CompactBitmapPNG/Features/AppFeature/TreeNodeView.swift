import AppKit
import SwiftUI

/// Renders a tree node, recursing into a `DisclosureGroup` for folders. Expansion state is
/// keyed by the node's stable path `id` and defaults to expanded, so newly discovered folders
/// (from a fresh selection or drop) show their contents immediately instead of collapsed.
struct TreeNodeView: View {
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

struct TreeNodeRowView: View {
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
            fileRow(for: row)
        }
    }

    private func fileRow(for row: FileRow) -> some View {
        let presentation = row.statusPresentation

        let content = HStack(spacing: 10) {
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
        .contentShape(Rectangle())

        return Group {
            if let openableFileURL = row.openableFileURL {
                Button {
                    NSWorkspace.shared.open(openableFileURL)
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .help(L10n.string("fileRow.openHelp"))
            } else {
                content
            }
        }
        .accessibilityIdentifier("file-row-\(row.displayName)")
    }
}
