import Foundation

actor ProcessingPipeline {
    func discoverSupportedFiles(from urls: [URL]) -> [DiscoveredFile] {
        var results: [DiscoveredFile] = []
        var seen: Set<URL> = []

        for url in urls {
            if isDirectory(url) {
                let files = enumerateSupportedFiles(in: url)
                for file in files where seen.insert(file.url.standardizedFileURL).inserted {
                    results.append(file)
                }
            } else if let file = makeDiscoveredFile(for: url),
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

    func processPNGs(urls: [URL]) async -> [PNGCompressionResult] {
        guard !urls.isEmpty else { return [] }

        return await withTaskGroup(of: (Int, PNGCompressionResult).self, returning: [PNGCompressionResult].self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let result: PNGCompressionResult

                    do {
                        result = try PNGOptimizer.optimize(url: url)
                    } catch {
                        result = PNGCompressionResult(
                            sourceURL: url,
                            outputURL: nil,
                            originalBytes: (try? Data(contentsOf: url).count) ?? 0,
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
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [DiscoveredFile] = []
        for case let fileURL as URL in enumerator {
            if let file = makeDiscoveredFile(for: fileURL) {
                results.append(file)
            }
        }

        return results
    }

    private func makeDiscoveredFile(for url: URL) -> DiscoveredFile? {
        guard !isDirectory(url) else { return nil }

        switch url.pathExtension.lowercased() {
        case "png":
            return DiscoveredFile(url: url, kind: .png)
        case "pdf":
            return DiscoveredFile(url: url, kind: .pdf)
        default:
            return nil
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
