import MlisbKit
import PDFKit
import XCTest

/// These run inside the sandboxed app, where WebKit and printing behave differently.
@MainActor final class SandboxTests: XCTestCase {
    private let markdown = "# Title\n\nSome text.\n\n```mermaid\ngraph TD\n  A --> B\n```\n\n```d2\nx -> y\n```\n"

    func testDiagramsRender() async throws {
        let mermaid = try await RenderService.shared.render(.mermaid, source: "graph TD\n  A --> B", theme: .dark)
        XCTAssertNotNil(PDFDocument(data: mermaid.pdf))
        let d2 = try await RenderService.shared.render(.d2, source: "x -> y", theme: .light)
        XCTAssertTrue(d2.svg.contains("<svg"))
    }

    func testEveryExportFormat() async throws {
        let html = await Exporter.html(markdown: markdown, title: "T", baseURL: nil)
        XCTAssertTrue(html.contains("<svg"))
        XCTAssertFalse(html.contains("language-mermaid") || html.contains("language-d2"), "both diagrams rendered")

        let pdf = try await Exporter.data(.pdf, markdown: markdown, title: "T", baseURL: nil)
        XCTAssertEqual(PDFDocument(data: pdf)?.string?.contains("Some text"), true)

        let jpeg = try await Exporter.data(.jpeg, markdown: markdown, title: "T", baseURL: nil)
        XCTAssertNotNil(NSImage(data: jpeg))

        let epub = try await Exporter.data(.epub, markdown: markdown, title: "T", baseURL: nil)
        XCTAssertEqual(epub.prefix(2), Data("PK".utf8))

        let plain = await Exporter.plainText(markdown: markdown)
        XCTAssertTrue(plain.contains("Title") && !plain.contains("#"))
    }
}
