import AppKit
import Foundation
import PDFKit
import Testing
@testable import MlisbKit

@MainActor
@Suite(.serialized)
struct ExportTests {
    let md = """
    # Heading One

    Some **bold** text and `code`.

    | A | B |
    |---|---|
    | 1 | 2 |

    ```swift
    let x = 1
    ```

    - [x] done
    - [ ] todo

    ```mermaid
    flowchart LR
     A --> B
    ```

    ```d2
    x -> y
    ```
    """

    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func htmlStructureAndDiagrams() async {
        let html = await Exporter.html(markdown: md, title: "T", baseURL: nil)
        for needle in ["<h1>", "<table>", "<pre><code class=\"language-swift\">", "type=\"checkbox\" checked", "<title>T</title>"] {
            #expect(html.contains(needle), "missing \(needle)")
        }
        #expect(html.components(separatedBy: "<svg").count - 1 >= 2)
        #expect(!html.contains("language-mermaid") && !html.contains("language-d2"))
    }

    @Test func brokenDiagramStaysCode() async {
        let html = await Exporter.html(markdown: "```mermaid\nflowchart LR\n A --> --> ((\n```", title: "T", baseURL: nil)
        #expect(html.contains("language-mermaid"))
        #expect(!html.contains("<svg"))
    }

    @Test func localImageInlined() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .representation(using: .png, properties: [:])!
        try png.write(to: dir.appendingPathComponent("pic one.png"))
        let html = await Exporter.html(markdown: "![a](pic%20one.png)\n\n![b](missing.png)\n\n![c](https://example.com/c.png)",
                                       title: "T", baseURL: dir)
        #expect(html.contains("<img src=\"data:image/png;base64,"))
        #expect(html.contains("src=\"missing.png\""))
        #expect(html.contains("src=\"https://example.com/c.png\""))
    }

    @Test func untrustedInputDoesNotInject() async {
        let evil = "</style><script>alert(1)</script>\n\n\"><img>\n\n[x](javascript:alert(1))"
        let html = await Exporter.html(markdown: evil, title: "</title><script>alert(2)</script>\"><img>", baseURL: nil)
        #expect(!html.contains("<script"))
        #expect(!html.contains("<img>"))
        #expect(!html.contains("javascript:"))
        #expect(html.components(separatedBy: "</style>").count == 2)
        #expect(html.components(separatedBy: "</title>").count == 2)
    }

    @Test func pdfPaginates() async throws {
        let long = (1...150).map { "Paragraph \($0) with some words to fill the page." }.joined(separator: "\n\n")
        let data = try await Exporter.data(.pdf, markdown: "# Long\n\n" + long, title: "Long", baseURL: nil)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "%PDF")
        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount > 1)
        #expect(doc.string?.contains("Paragraph 150") == true)
    }

    @Test func jpegDecodes() async throws {
        let data = try await Exporter.data(.jpeg, markdown: md, title: "T", baseURL: nil)
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
        #expect(rep.pixelsWide == 1600)
        #expect(rep.pixelsHigh > 200)
    }

    @Test func epubIsValid() async throws {
        let data = try await Exporter.data(.epub, markdown: md, title: "A & B", baseURL: nil)
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("book.epub")
        try data.write(to: file)

        func run(_ args: [String]) throws -> (Int32, Data) {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = args
            p.standardOutput = pipe
            try p.run()
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, out)
        }
        #expect(try run(["-tq", file.path]).0 == 0)

        // First local header: method (offset 8) stored, name "mimetype", then its content.
        let method = data[8] | data[9]
        let nameLen = Int(data[26]) + Int(data[27]) << 8
        #expect(method == 0)
        #expect(String(decoding: data[30..<(30 + nameLen)], as: UTF8.self) == "mimetype")
        #expect(String(decoding: data[(30 + nameLen)..<(30 + nameLen + 20)], as: UTF8.self) == "application/epub+zip")

        let chapter = try run(["-p", file.path, "OEBPS/chapter.xhtml"]).1
        let parser = XMLParser(data: chapter)
        #expect(parser.parse(), "\(String(describing: parser.parserError))")
        #expect(String(decoding: chapter, as: UTF8.self).contains("images/diagram1.png"))
        let opf = XMLParser(data: try run(["-p", file.path, "OEBPS/content.opf"]).1)
        #expect(opf.parse())
    }

    @Test func plainTextHasNoSyntax() async {
        let text = await Exporter.plainText(markdown: "# Title\n\nSome **bold** and `code` words.\n\n- one\n- two")
        for word in ["Title", "bold", "code", "words", "one", "two"] { #expect(text.contains(word)) }
        for syntax in ["#", "**", "`"] { #expect(!text.contains(syntax)) }
    }
}
