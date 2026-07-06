import Foundation

enum SupportedFileKind: String, Sendable, Equatable {
    case png = "PNG"
    case pdf = "PDF"
}

enum PNGCompressionStatus: Sendable, Equatable {
    case optimized
    case unchanged
    case failed
}

enum PNGQuantizationLevel: Int, CaseIterable, Identifiable, Sendable, Equatable {
    case colors256 = 256
    case colors128 = 128
    case colors64 = 64

    var id: Int { rawValue }

    var label: String {
        "\(rawValue) colors"
    }
}

struct PNGCompressionSettings: Sendable, Equatable {
    var enableAdaptiveQuantization = false
    var quantizationLevel: PNGQuantizationLevel = .colors256
}

struct PNGCompressionResult: Identifiable, Sendable, Equatable {
    var id: URL { sourceURL }
    let sourceURL: URL
    let outputURL: URL?
    let originalBytes: Int
    let compressedBytes: Int?
    let status: PNGCompressionStatus
    let message: String

    var savingsBytes: Int? {
        guard let compressedBytes else { return nil }
        return originalBytes - compressedBytes
    }

    var savingsPercent: Double? {
        guard
            let savingsBytes,
            originalBytes > 0
        else {
            return nil
        }

        return (Double(savingsBytes) / Double(originalBytes)) * 100
    }

    var statusLabel: String {
        switch status {
        case .optimized:
            return "Compressed"
        case .unchanged:
            return "No Change"
        case .failed:
            return "Failed"
        }
    }
}

enum PDFContentStatus: Sendable, Equatable {
    case mixed
    case vectorOnly
    case rasterOnly
    case noDrawingData
    case failed
}

struct PDFAnalysisResult: Identifiable, Sendable, Equatable {
    var id: URL { pdfURL }
    let pdfURL: URL
    let pageCount: Int
    let hasVectorContent: Bool
    let hasRasterImages: Bool
    let hasText: Bool
    let status: PDFContentStatus
    let message: String

    var statusLabel: String {
        switch status {
        case .mixed:
            return "Vector + Raster"
        case .vectorOnly:
            return "Vector/Text"
        case .rasterOnly:
            return "Raster Only"
        case .noDrawingData:
            return "No Drawing Data"
        case .failed:
            return "Failed"
        }
    }
}

enum ProcessingState: Sendable, Equatable {
    case idle
    case running(String)
}

struct IntakeSummary: Sendable, Equatable {
    let acceptedPNGCount: Int
    let acceptedPDFCount: Int
    let skippedUnsupportedCount: Int
    let skippedDisabledCount: Int

    var description: String {
        let parts = [
            acceptedPNGCount > 0 ? "\(acceptedPNGCount) PNG" + (acceptedPNGCount == 1 ? "" : "s") : nil,
            acceptedPDFCount > 0 ? "\(acceptedPDFCount) PDF" + (acceptedPDFCount == 1 ? "" : "s") : nil
        ].compactMap { $0 }

        let acceptedText = parts.isEmpty ? "No supported files were queued." : "Queued " + parts.joined(separator: " and ") + "."
        let unsupportedText = skippedUnsupportedCount > 0 ? " Ignored \(skippedUnsupportedCount) unsupported item" + (skippedUnsupportedCount == 1 ? "." : "s.") : ""
        let disabledText = skippedDisabledCount > 0 ? " Skipped \(skippedDisabledCount) file" + (skippedDisabledCount == 1 ? "" : "s") + " because their operation is disabled." : ""

        return acceptedText + unsupportedText + disabledText
    }
}

struct DiscoveredFile: Sendable, Equatable {
    let url: URL
    let kind: SupportedFileKind?
}

func byteCountDescription(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
