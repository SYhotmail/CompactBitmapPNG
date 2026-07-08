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
        L10n.plural("quantization.colorsCount", rawValue)
    }
}

struct PNGCompressionSettings: Sendable, Equatable {
    var quantizationLevel: PNGQuantizationLevel? = .colors256
    var overwriteOriginal: Bool = true
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
            return L10n.string("status.png.compressed")
        case .unchanged:
            return L10n.string("status.png.noChange")
        case .failed:
            return L10n.string("status.failed")
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
            return L10n.string("status.pdf.mixed")
        case .vectorOnly:
            return L10n.string("status.pdf.vectorOnly")
        case .rasterOnly:
            return L10n.string("status.pdf.rasterOnly")
        case .noDrawingData:
            return L10n.string("status.pdf.noDrawingData")
        case .failed:
            return L10n.string("status.failed")
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
            acceptedPNGCount > 0 ? L10n.plural("intake.pngCount", acceptedPNGCount) : nil,
            acceptedPDFCount > 0 ? L10n.plural("intake.pdfCount", acceptedPDFCount) : nil
        ].compactMap { $0 }

        let acceptedText = parts.isEmpty
            ? L10n.string("intake.noneQueued")
            : L10n.format("intake.queued", parts.joined(separator: L10n.string("intake.joiner")))

        let unsupportedText = skippedUnsupportedCount > 0
            ? L10n.format("intake.ignoredUnsupported", L10n.plural("intake.unsupportedCount", skippedUnsupportedCount))
            : ""

        let disabledText = skippedDisabledCount > 0
            ? L10n.format("intake.skippedDisabled", L10n.plural("intake.disabledCount", skippedDisabledCount))
            : ""

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
