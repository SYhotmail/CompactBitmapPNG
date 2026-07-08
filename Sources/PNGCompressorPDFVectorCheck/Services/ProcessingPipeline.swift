import Foundation

struct ProcessingPipeline: @unchecked Sendable {
    
    let fileManager: FileManager = .default

    @concurrent
    func discoverSupportedFiles(from urls: [URL]) async -> [DiscoveredFile] {
        let task = Task {
            discoverSupportedFilesCore(from: urls)
        }
        
        return await task.value
    }
    
    private func discoverSupportedFilesCore(from urls: [URL]) -> [DiscoveredFile] {
        var results: [DiscoveredFile] = []
        var seen: Set<URL> = []

        for url in urls {
            if Self.isDirectory(url) {
                let files = enumerateSupportedFiles(in: url)
                for file in files where seen.insert(file.url.standardizedFileURL).inserted {
                    results.append(file)
                }
            } else if let file = Self.makeDiscoveredFile(for: url),
                      seen.insert(file.url.standardizedFileURL).inserted {
                results.append(file)
            } else if seen.insert(url.standardizedFileURL).inserted {
                results.append(DiscoveredFile(url: url, kind: nil))
            }
        }

        return results.sorted {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    @concurrent
    func processPNGs(urls: [URL], settings: PNGCompressionSettings) async -> [PNGCompressionResult] {
        guard !urls.isEmpty else { return [] }

        return await withTaskGroup(of: (Int, PNGCompressionResult).self, returning: [PNGCompressionResult].self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let result: PNGCompressionResult

                    do {
                        result = try PNGOptimizer.optimize(url: url, settings: settings)
                    } catch {
                        let originalBytes = (try? url.fileSizeInBytes(fileManager: fileManager)) ?? UInt64((try? Data(contentsOf: url).count) ?? 0)
                                             
                        result = PNGCompressionResult(
                            sourceURL: url,
                            outputURL: nil,
                            originalBytes: originalBytes,
                            compressedBytes: nil,
                            status: .failed,
                            message: error.localizedDescription
                        )
                    }

                    return (index, result)
                }
            }

            var ordered = Array<PNGCompressionResult?>(repeating: nil, count: urls.count)
            for await (index, result) in group {
                ordered[index] = result
            }

            return ordered.compactMap { $0 }
        }
    }

    @concurrent
    func processPDFs(urls: [URL]) async -> [PDFAnalysisResult] {
        guard !urls.isEmpty else { return [] }

        return await withTaskGroup(of: (Int, PDFAnalysisResult).self, returning: [PDFAnalysisResult].self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let result: PDFAnalysisResult

                    do {
                        result = try PDFVectorAnalyzer.analyze(url: url)
                    } catch {
                        result = PDFAnalysisResult(
                            pdfURL: url,
                            pageCount: 0,
                            hasVectorContent: false,
                            hasRasterImages: false,
                            hasText: false,
                            status: .failed,
                            message: error.localizedDescription
                        )
                    }

                    return (index, result)
                }
            }

            var ordered = Array<PDFAnalysisResult?>(repeating: nil, count: urls.count)
            for await (index, result) in group {
                ordered[index] = result
            }

            return ordered.compactMap { $0 }
        }
    }

    private func enumerateSupportedFiles(in folderURL: URL) -> [DiscoveredFile] {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [DiscoveredFile] = []
        for case let fileURL as URL in enumerator {
            if let file = Self.makeDiscoveredFile(for: fileURL) {
                results.append(file)
            }
        }

        return results
    }

    private static func makeDiscoveredFile(for url: URL) -> DiscoveredFile? {
        let ext = url.pathExtension.lowercased()
        
        guard let kind = SupportedFileKind(rawValue: ext) else {
            return nil
        }
        
        guard !isDirectory(url) else { return nil }
        
        return DiscoveredFile(url: url, kind: kind)
    }

    private static func isDirectoryCore(_ url: URL) throws -> Bool? {
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
    }
    
    private static func isDirectory(_ url: URL) -> Bool {
        (try? isDirectoryCore(url)) == true
    }
}
