import Foundation

/// Hand-builds minimal, uncompressed one-page PDFs byte-for-byte so tests can exercise exact
/// content-stream operator sequences and resource structures that CoreGraphics's own PDF writer
/// (`CGContext(consumer:mediaBox:)`) doesn't give fine control over — e.g. a Quartz-style
/// clip-wrapped image, a CMYK raw image, or two images on one page.
enum PDFFixtureBuilder {
    /// - Parameters:
    ///   - resources: the page's `/Resources` dictionary, written verbatim (e.g.
    ///     `"<< /XObject << /Im1 5 0 R >> >>"`).
    ///   - contentStream: the page's content stream operators, written verbatim and uncompressed.
    ///   - extraObjects: additional indirect objects (XObjects, etc.), numbered starting at 5,
    ///     referenced by `resources`. Each is the object body only (no "N 0 obj"/"endobj" wrapper).
    static func build(
        mediaBoxWidth: Int,
        mediaBoxHeight: Int,
        resources: String,
        contentStream: String,
        extraObjects: [Data] = []
    ) -> Data {
        var objects: [Data] = []
        objects.append(Data("<< /Type /Catalog /Pages 2 0 R >>".utf8))
        objects.append(Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8))
        objects.append(Data("""
        << /Type /Page /Parent 2 0 R /MediaBox [0 0 \(mediaBoxWidth) \(mediaBoxHeight)] \
        /Resources \(resources) /Contents 4 0 R >>
        """.utf8))

        let contentBytes = Data(contentStream.utf8)
        var contentObject = Data("<< /Length \(contentBytes.count) >>\nstream\n".utf8)
        contentObject.append(contentBytes)
        contentObject.append(Data("\nendstream".utf8))
        objects.append(contentObject)

        objects.append(contentsOf: extraObjects)

        var output = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(output.count)
            output.append(Data("\(index + 1) 0 obj\n".utf8))
            output.append(object)
            output.append(Data("\nendobj\n".utf8))
        }

        let xrefOffset = output.count
        output.append(Data("xref\n0 \(objects.count + 1)\n".utf8))
        output.append(Data("0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            output.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        output.append(Data("""
        trailer
        << /Size \(objects.count + 1) /Root 1 0 R >>
        startxref
        \(xrefOffset)
        %%EOF
        """.utf8))

        return output
    }

    static func write(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).pdf")
        try data.write(to: url)
        return url
    }

    /// A raw (unfiltered), 8-bit-per-component image XObject body — solid-color RGB by default,
    /// so recompression can reliably beat it (uncompressed samples, no entropy coding at all).
    static func rawImageObject(
        width: Int,
        height: Int,
        colorSpace: String = "/DeviceRGB",
        componentsPerPixel: Int = 3,
        pixel: [UInt8] = [200, 60, 30],
        smaskObjectNumber: Int? = nil
    ) -> Data {
        var samples = [UInt8]()
        samples.reserveCapacity(width * height * componentsPerPixel)
        for _ in 0..<(width * height) {
            samples.append(contentsOf: pixel)
        }

        let smaskEntry = smaskObjectNumber.map { " /SMask \($0) 0 R" } ?? ""
        // Note: a triple-quoted literal ending right at "stream" would have Swift trim the
        // trailing newline before the closing `"""`, gluing the binary sample data directly onto
        // the `stream` keyword with no EOL separator — invalid per the PDF spec. Using an explicit
        // "\n" here avoids that trap.
        var object = Data("""
        << /Type /XObject /Subtype /Image /Width \(width) /Height \(height) \
        /ColorSpace \(colorSpace) /BitsPerComponent 8\(smaskEntry) /Length \(samples.count) >>
        """.utf8)
        object.append(Data("\nstream\n".utf8))
        object.append(Data(samples))
        object.append(Data("\nendstream".utf8))
        return object
    }

    /// A single-component (DeviceGray) raw image, suitable as an `/SMask`.
    static func rawGrayMaskObject(width: Int, height: Int, value: UInt8 = 255) -> Data {
        rawImageObject(
            width: width,
            height: height,
            colorSpace: "/DeviceGray",
            componentsPerPixel: 1,
            pixel: [value]
        )
    }

    /// An `/ICCBased` color space stream object — just the `/N` (component count) and `/Alternate`
    /// entries that `PDFBitmapCompressor` actually reads; the profile data itself is empty since
    /// nothing in this codebase parses it. Referenced from an image's `/ColorSpace` as
    /// `"[/ICCBased N 0 R]"`, where `N` is this object's number in `extraObjects`.
    static func iccBasedColorSpaceObject(componentsPerPixel: Int) -> Data {
        let alternate: String
        switch componentsPerPixel {
        case 1: alternate = "/DeviceGray"
        case 4: alternate = "/DeviceCMYK"
        default: alternate = "/DeviceRGB"
        }

        var object = Data("<< /N \(componentsPerPixel) /Alternate \(alternate) /Length 0 >>".utf8)
        object.append(Data("\nstream\n".utf8))
        object.append(Data("\nendstream".utf8))
        return object
    }
}
