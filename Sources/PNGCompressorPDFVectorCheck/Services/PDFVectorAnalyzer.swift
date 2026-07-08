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

    static func scan(page: CGPDFPage) -> PageScanState {
        let state = PageScanState(resources: resourcesDictionary(for: page))

        let contentStream = CGPDFContentStreamCreateWithPage(page)
        guard let operatorTable = CGPDFOperatorTableCreate() else {
            return state
        }

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

            let name = String(cString: objectName)
            switch state.subtypeForXObject(named: name) {
            case "Image":
                state.hasRasterImages = true
                state.imageXObjectNames.insert(name)
            case "Form":
                state.hasVectorContent = true
            default:
                break
            }
        }

        // Only operators that actually paint a mark count as vector content. Path-construction
        // operators (m, l, c, v, y, h, re) and the no-op path terminator `n` don't by themselves
        // draw anything — `re W n` (build a rect, clip to it, discard the path unpainted) is the
        // standard boilerplate macOS's own Quartz PDF writer wraps every embedded image in, so
        // counting it as vector content would misclassify practically every screenshot-saved-as-
        // PDF as "mixed" instead of "raster only".
        for op in ["S", "s", "f", "F", "f*", "B", "B*", "b", "b*", "sh"] {
            CGPDFOperatorTableSetCallback(operatorTable, op, markVector)
        }

        for op in ["BT", "ET", "Tj", "TJ", "'", "\""] {
            CGPDFOperatorTableSetCallback(operatorTable, op, markText)
        }

        CGPDFOperatorTableSetCallback(operatorTable, "BI", markInlineImage)
        CGPDFOperatorTableSetCallback(operatorTable, "Do", markDo)

        // The operator table must be fully populated *before* the scanner is created — the
        // scanner captures its own reference to the table's registered callbacks at creation
        // time, so registering callbacks afterward is silently a no-op and nothing ever fires.
        let scanner = CGPDFScannerCreate(contentStream, operatorTable, state.pointer)
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
            return L10n.string("pdf.summary.mixed")
        }

        if state.hasVectorContent {
            return L10n.string("pdf.summary.vectorOnly")
        }

        if state.hasRasterImages {
            return L10n.string("pdf.summary.rasterOnly")
        }

        return L10n.string("pdf.summary.none")
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
            return L10n.string("error.pdf.openFailed")
        }
    }
}

final class PageScanState {
    var hasVectorContent = false
    var hasRasterImages = false
    var hasText = false
    var imageXObjectNames: Set<String> = []

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
        guard let stream = imageStream(named: name),
              let dictionary = CGPDFStreamGetDictionary(stream) else {
            return nil
        }

        var subtypeName: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtypeName),
              let subtypeName else {
            return nil
        }

        return String(cString: subtypeName)
    }

    /// Looks up the raw stream backing an `XObject` (image or form) by name, regardless of its
    /// subtype — used by `PDFBitmapCompressor` to pull the actual image bytes for recompression.
    func imageStream(named name: String) -> CGPDFStreamRef? {
        guard let resources else {
            return nil
        }

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

        return stream
    }
}
