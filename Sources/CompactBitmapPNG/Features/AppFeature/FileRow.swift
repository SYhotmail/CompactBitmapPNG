import SwiftUI

struct FileRow: Identifiable {
    enum Kind {
        case png
        case pdf
    }

    enum Status {
        case pending
        case png(PNGCompressionResult)
        case pdf(PDFAnalysisResult, PDFCompressionResult?)
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
                    let percentText = percent.formatted(.number.precision(.fractionLength(1)))
                    detail = "\(byteCountDescription(result.originalBytes)) → \(byteCountDescription(compressedBytes)) (-\(percentText)%)"
                } else {
                    detail = result.message
                }
                return StatusPresentation(label: result.statusLabel, tint: .green, symbolName: "checkmark.circle.fill", isPending: false, detail: detail)

            case .unchanged:
                return StatusPresentation(
                    label: result.statusLabel,
                    tint: .orange,
                    symbolName: "minus.circle.fill",
                    isPending: false,
                    detail: byteCountDescription(result.originalBytes)
                )

            case .failed:
                return StatusPresentation(label: result.statusLabel, tint: .red, symbolName: "xmark.circle.fill", isPending: false, detail: result.message)
            }

        case let .pdf(result, compression):
            let detail: String
            if let compression, compression.status == .compressed, let compressedBytes = compression.compressedBytes {
                let percentText = compression.savingsPercent?.formatted(.number.precision(.fractionLength(1))) ?? "0"
                detail = "\(byteCountDescription(compression.originalBytes)) → \(byteCountDescription(compressedBytes)) (-\(percentText)%)"
            } else {
                detail = L10n.plural("pdf.pageCount", result.pageCount)
            }

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

struct StatusPresentation {
    let label: String
    let tint: Color
    let symbolName: String?
    let isPending: Bool
    let detail: String
}
