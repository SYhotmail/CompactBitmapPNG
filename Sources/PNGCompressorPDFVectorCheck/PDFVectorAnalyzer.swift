import CoreGraphics
import Foundation

enum PDFVectorAnalyzer {
    static func analyze(url: URL) throws -> PDFAnalysisResult {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw PDFVectorAnalyzerError.failedToOpen
        }

        let pageCount = document.numberOfPages
        let aggregate = PageScanState()

        for pageIndex in 1...pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageState = scan(page: page)
            aggregate.merge(pageState)
        }

        let message = summaryMessage(for: aggregate)

        return PDFAnalysisResult(
            pdfURL: url,
            pageCount: pageCount,
            hasVectorContent: aggregate.hasVectorContent,
            hasRasterImages: aggregate.hasRasterImages,
            hasText: aggregate.hasText,
            status: status(for: aggregate),
            message: message
        )
    }

    private static func scan(page: CGPDFPage) -> PageScanState {
        let state = PageScanState(resources: resourcesDictionary(for: page))

        let contentStream = CGPDFContentStreamCreateWithPage(page)
        guard let operatorTable = CGPDFOperatorTableCreate() else {
            return state
        }
        let scanner = CGPDFScannerCreate(contentStream, operatorTable, state.pointer)

        let markVector: CGPDFOperatorCallback = { _, info in
            guard let info else { return }
            Unmanaged<PageScanState>.fromOpaque(info).takeUnretainedValue().hasVectorContent = true
        }

        let markText: CGPDFOperatorCallback = { _, info in
            guard let info else { return }
            let state = Unmanaged<PageScanState>.fromOpaque(info).takeUnretainedValue()
            state.hasText = true
            state.hasVectorContent = true
        }

        let markInlineImage: CGPDFOperatorCallback = { _, info in
            guard let info else { return }
            Unmanaged<PageScanState>.fromOpaque(info).takeUnretainedValue().hasRasterImages = true
        }

        let markDo: CGPDFOperatorCallback = { scanner, info in
            guard let info else { return }
            let state = Unmanaged<PageScanState>.fromOpaque(info).takeUnretainedValue()

            var objectName: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &objectName), let objectName else { return }

            switch state.subtypeForXObject(named: String(cString: objectName)) {
            case "Image":
                state.hasRasterImages = true
            case "Form":
                state.hasVectorContent = true
            default:
                break
            }
        }

        for op in ["m", "l", "c", "v", "y", "h", "re", "S", "s", "f", "F", "f*", "B", "B*", "b", "b*", "n", "sh"] {
            CGPDFOperatorTableSetCallback(operatorTable, op, markVector)
        }

        for op in ["BT", "ET", "Tj", "TJ", "'", "\""] {
            CGPDFOperatorTableSetCallback(operatorTable, op, markText)
        }

        CGPDFOperatorTableSetCallback(operatorTable, "BI", markInlineImage)
        CGPDFOperatorTableSetCallback(operatorTable, "Do", markDo)
        CGPDFScannerScan(scanner)

        return state
    }

    private static func resourcesDictionary(for page: CGPDFPage) -> CGPDFDictionaryRef? {
        guard let pageDictionary = page.dictionary else {
            return nil
        }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources) else {
            return nil
        }

        return resources
    }

    private static func summaryMessage(for state: PageScanState) -> String {
        if state.hasVectorContent && state.hasRasterImages {
            return "This PDF contains vector/text content and raster images."
        }

        if state.hasVectorContent {
            return "This PDF contains vector or text drawing commands."
        }

        if state.hasRasterImages {
            return "This PDF appears to be raster-image based only."
        }

        return "No vector or raster drawing operators were detected."
    }

    private static func status(for state: PageScanState) -> PDFContentStatus {
        if state.hasVectorContent && state.hasRasterImages {
            return .mixed
        }

        if state.hasVectorContent {
            return .vectorOnly
        }

        if state.hasRasterImages {
            return .rasterOnly
        }

        return .noDrawingData
    }
}

enum PDFVectorAnalyzerError: LocalizedError {
    case failedToOpen

    var errorDescription: String? {
        switch self {
        case .failedToOpen:
            return "The PDF file could not be opened."
        }
    }
}

final class PageScanState {
    var hasVectorContent = false
    var hasRasterImages = false
    var hasText = false

    private let resources: CGPDFDictionaryRef?

    init(resources: CGPDFDictionaryRef? = nil) {
        self.resources = resources
    }

    var pointer: UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    func merge(_ other: PageScanState) {
        hasVectorContent = hasVectorContent || other.hasVectorContent
        hasRasterImages = hasRasterImages || other.hasRasterImages
        hasText = hasText || other.hasText
    }

    func subtypeForXObject(named name: String) -> String? {
        guard let resources else { return nil }

        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects),
              let xObjects else {
            return nil
        }

        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(xObjects, name, &stream),
              let stream else {
            return nil
        }

        guard let dictionary = CGPDFStreamGetDictionary(stream) else {
            return nil
        }

        var subtypeName: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtypeName),
              let subtypeName else {
            return nil
        }

        return String(cString: subtypeName)
    }
}
