import AppKit
import Foundation
import Testing

@testable import mlisb

struct ThumbnailTextTests {
    @Test func headingBecomesTitleAndRestIsStripped() {
        let r = ThumbnailText.select(from: "intro\n# **Big** `title`\n\nSee [docs](http://x.y) and *this*.\n- item one\n")
        #expect(r.title == "Big title")
        #expect(r.body == ["See docs and this.", "item one"])
    }

    @Test func frontMatterAndCodeFencesAreSkipped() {
        let r = ThumbnailText.select(from: "---\ntitle: x\n---\n# Head\n```swift\nlet a = 1\n```\ntext\n~~~\nhidden\n~~~\n")
        #expect(r.title == "Head")
        #expect(r.body == ["text"])
    }

    @Test func noHeadingUsesFirstNonEmptyLine() {
        let r = ThumbnailText.select(from: "\n\nfirst line\nsecond\n")
        #expect(r.title == "first line")
        #expect(r.body == ["second"])
    }

    @Test func emptyFile() {
        #expect(ThumbnailText.select(from: "").title == nil)
        #expect(ThumbnailText.select(from: "---\na: b\n---\n").body.isEmpty)
    }

    @Test func pageHasPaperProportions() {
        let size = ThumbnailPage.size(fitting: CGSize(width: 512, height: 512))
        #expect(abs(size.height / size.width - 1.414) < 0.01)
        #expect(size.height == 512)
    }

    @Test func drawsPaperAndInk() throws {
        let size = NSSize(width: 240, height: 340)
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 340, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        ThumbnailPage.draw(ThumbnailText.select(from: "---\na: b\n---\n# Hello Quick Look\n\nSome **bold** text with a [link](http://a.b) and `code`.\n\n- one\n- two\n\nMore prose here to fill the page, long enough to wrap onto a second line of the page column.\n"), in: size, textVisible: true)
        NSGraphicsContext.restoreGraphicsState()
        #expect(rep.colorAt(x: 2, y: 2)?.redComponent ?? 0 > 0.9)
        var dark = false
        for y in 0..<340 { for x in 0..<240 where (rep.colorAt(x: x, y: y)?.redComponent ?? 1) < 0.5 { dark = true } }
        #expect(dark)
    }
}

struct PreviewContentTests {
    private func load(_ data: Data) throws -> PreviewContent {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try PreviewContent.load(url)
    }

    @Test func smallFile() throws {
        #expect(try load(Data("# hi".utf8)) == .text("# hi", truncated: false))
    }

    @Test func largeFileIsCutAtOneMegabyteOnACharacterBoundary() throws {
        let data = Data(repeating: UInt8(ascii: "a"), count: PreviewContent.maxBytes - 1) + Data("é tail".utf8)
        guard case .text(let text, let truncated) = try load(data) else { Issue.record("not text"); return }
        #expect(truncated)
        #expect(text.utf8.count == PreviewContent.maxBytes - 1)
    }

    @Test func nonUTF8() throws {
        #expect(try load(Data([0xFF, 0xFE, 0x41, 0x00])) == .notUTF8)
    }
}
