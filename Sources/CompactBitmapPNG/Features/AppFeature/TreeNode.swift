import Foundation

/// A node in the file/folder tree shown in the main window. Folder nodes carry a non-nil
/// (possibly empty) `children` array so SwiftUI's `List` draws a disclosure triangle; leaf
/// nodes carry `nil` so they render as plain rows.
struct TreeNode: Identifiable {
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
func buildTree(rootSelections: [URL], fileRows: [FileRow]) -> [TreeNode] {
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
