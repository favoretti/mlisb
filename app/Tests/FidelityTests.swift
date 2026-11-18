import MarkdownEngine
import SwiftUI
import XCTest
@testable import mlisb

@MainActor private final class Box { var text: String; init(_ text: String) { self.text = text } }

@MainActor final class FidelityTests: XCTestCase {
    static let samples: [String] = [
        "# Title\n\nPlain paragraph with **bold**, *italic*, `code` and a [link](https://example.com).\n",
        "No trailing newline",
        "Trailing spaces   \nhard break above\n\n\n\nmany blank lines\n",
        "Windows\r\nline\r\nendings\r\n",
        "\tTab indented\n\t- list with tab\n* star list\n+ plus list\n1) paren list\n",
        "- a\n  - nested\n    - deeper\n  lazy continuation\n- [ ] todo\n- [x] done\n",
        "| a | b |\n|:--|--:|\n| 1 | 2 |\n\n|compact|table|\n|-|-|\n|x|y|\n",
        "Setext\n======\n\nSecond\n------\n\n***\n___\n",
        "```mermaid\ngraph TD\n  A-->B\n```\n\n```d2\nx -> y\n```\n\n~~~\ntilde fence\n~~~\n",
        "[[Wiki Link]] and [[Name|id-123]] and ![[embed.png]] and ![alt](./img.png)\n",
        "\"straight quotes\" -- dashes ... 'single' <div align=\"center\">html</div>\n",
        "---\ntitle: front matter\n---\n\n[ref]: https://example.com \"Title\"\n\nFootnote[^1].\n\n[^1]: note\n",
        "$$\nx^2\n$$\n\nInline $a+b$ and ==highlight== and ~~strike~~ and <u>underline</u>\n",
        "\u{FEFF}BOM first\n",
        "Unicode: café (precomposed) cafe\u{301} (combining) 👩‍👩‍👧 \u{00A0}nbsp\n",
    ]

    /// Mounting the editor on a document must not rewrite a single character.
    func testOpeningADocumentDoesNotChangeItsText() async throws {
        for raw in [false, true] {
            for sample in Self.samples {
                let box = Box(sample)
                var config = MarkdownEditorConfiguration.default
                config.rawSourceMode = raw
                let editor = NativeTextViewWrapper(
                    text: Binding(get: { box.text }, set: { box.text = $0 }), configuration: config)
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: editor)
                window.orderFront(nil)
                try await Task.sleep(for: .milliseconds(150))
                XCTAssertEqual(box.text, sample, "raw=\(raw)")
                window.close()
            }
        }
    }

    func testDocumentRoundTripAndExternalChanges() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = "line one\r\n\ttabbed   \nno newline at end"
        try Data(original.utf8).write(to: url)

        let document = Document(url: url)
        XCTAssertEqual(document.text, original)

        document.text += "!"
        document.save()
        XCTAssertEqual(try Data(contentsOf: url), Data((original + "!").utf8))

        // No local edits: an external change loads silently.
        try Data("from agent\n".utf8).write(to: url)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(document.text, "from agent\n")
        XCTAssertNil(document.conflictingDiskText)

        // Atomic replace (new inode) is still seen.
        try Data("atomic\n".utf8).write(to: url, options: .atomic)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(document.text, "atomic\n")

        // Unsaved local edits plus an external change: conflict, nothing overwritten.
        document.text = "mine\n"
        try Data("theirs\n".utf8).write(to: url)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(document.conflictingDiskText, "theirs\n")
        document.save()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "theirs\n")
        document.resolveConflict(keepMine: true)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "mine\n")
    }

    func testInvalidUTF8IsReadOnlyAndNeverSaved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data([0x68, 0x69, 0xFF, 0xFE])
        try bytes.write(to: url)
        let document = Document(url: url)
        XCTAssertTrue(document.isReadOnly)
        document.text = "oops"
        document.save()
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}
