import AppKit
import Foundation
import zlib

extension Exporter {
    static func epub(markdown: String, title: String, baseURL: URL?) async throws -> Data {
        var images: [(String, Data)] = []
        let body = await body(markdown, baseURL: baseURL) { language, source in
            guard let d = try? await RenderService.shared.render(language, source: source, theme: .light),
                  let png = png(fromPDF: d.pdf) else { return nil }
            let name = "images/diagram\(images.count + 1).png"
            images.append((name, png))
            return "<div class=\"diagram\"><img src=\"\(name)\" alt=\"Diagram\"/></div>"
        }
        // The renderer's own checkbox markup uses boolean attributes; XHTML needs them spelled out and void tags closed.
        let xhtml = body
            .replacingOccurrences(of: "<input type=\"checkbox\" checked disabled>", with: "<input type=\"checkbox\" checked=\"checked\" disabled=\"disabled\"/>")
            .replacingOccurrences(of: "<input type=\"checkbox\" disabled>", with: "<input type=\"checkbox\" disabled=\"disabled\"/>")
            .replacingOccurrences(of: #"<(hr|br|img)\b([^>]*?)\s*/?>"#, with: "<$1$2/>", options: .regularExpression)
        let t = escape(title)
        let ns = "xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"en\" xml:lang=\"en\""
        let chapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html \(ns)><head><meta charset="utf-8"/><title>\(t)</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body>
        \(xmlSafe(xhtml))
        </body></html>
        """
        let nav = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html \(ns)><head><meta charset="utf-8"/><title>\(t)</title></head>
        <body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">\(t)</a></li></ol></nav></body></html>
        """
        let manifestImages = images.enumerated().map {
            "<item id=\"img\($0.offset)\" href=\"\($0.element.0)\" media-type=\"image/png\"/>"
        }.joined(separator: "\n")
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id" xml:lang="en">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:uuid:\(UUID().uuidString)</dc:identifier>
        <dc:title>\(t)</dc:title><dc:language>en</dc:language>
        <meta property="dcterms:modified">\(ISO8601DateFormatter().string(from: Date()))</meta>
        </metadata>
        <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
        <item id="css" href="style.css" media-type="text/css"/>
        \(manifestImages)
        </manifest>
        <spine><itemref idref="chapter"/></spine>
        </package>
        """
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """
        var entries: [(String, Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/nav.xhtml", Data(nav.utf8)),
            ("OEBPS/chapter.xhtml", Data(chapter.utf8)),
            ("OEBPS/style.css", Data(css.utf8)),
        ]
        entries += images.map { ("OEBPS/" + $0.0, $0.1) }
        return zip(entries)
    }

    /// Drops characters XML 1.0 forbids.
    private static func xmlSafe(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\n" || $0 == "\t" || $0 == "\r" }))
    }

    private static func png(fromPDF pdf: Data) -> Data? {
        guard let rep = NSPDFImageRep(data: pdf) else { return nil }
        let w = Int(rep.bounds.width * 2), h = Int(rep.bounds.height * 2)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        rep.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        return bitmap.representation(using: .png, properties: [:])
    }

    /// ZIP with stored (uncompressed) entries, in the given order.
    private static func zip(_ entries: [(String, Data)]) -> Data {
        func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var out = Data(), central = Data()
        for (name, data) in entries {
            let n = Data(name.utf8)
            let crc = UInt32(truncatingIfNeeded: data.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)) })
            let fields = le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0x21)) + le(crc)
                + le(UInt32(data.count)) + le(UInt32(data.count)) + le(UInt16(n.count)) + le(UInt16(0))
            central += le(UInt32(0x02014b50)) + le(UInt16(20)) + le(UInt16(20)) + fields
                + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt32(0)) + le(UInt32(out.count)) + n
            out += le(UInt32(0x04034b50)) + le(UInt16(20)) + fields + n + data
        }
        let count = le(UInt16(entries.count))
        return out + central + le(UInt32(0x06054b50)) + le(UInt16(0)) + le(UInt16(0)) + count + count
            + le(UInt32(central.count)) + le(UInt32(out.count)) + le(UInt16(0))
    }
}
