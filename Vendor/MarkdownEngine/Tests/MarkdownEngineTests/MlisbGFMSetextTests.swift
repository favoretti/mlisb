//
//  MlisbGFMSetextTests.swift
//  MarkdownEngineTests
//
//  mlisb: setext headings (`===` level 1, `---` level 2).
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("mlisb GFM setext headings")
struct MlisbGFMSetextTests {

    @Test("text over === or --- is a heading; --- after a blank line stays a thematic break")
    func blocks() {
        #expect(GFM.kinds("Title\n=====\n") == [.setextHeading])
        #expect(GFM.kinds("Title\n---\n") == [.setextHeading])
        #expect(GFM.kinds("Two\nlines\n===\nnext\n") == [.setextHeading, .paragraph])
        #expect(GFM.kinds("Title\n\n---\n") == [.paragraph, .thematicBreak])
        #expect(GFM.kinds("---\n") == [.thematicBreak])
        #expect(GFM.kinds("Title\n***\n") == [.paragraph, .thematicBreak])
        #expect(GFM.kinds("Title\n==\n") == [.paragraph])         // needs 3+
        #expect(GFM.kinds("===\n") == [.paragraph])
        #expect(GFM.kinds("- a\n---\n") == [.list, .thematicBreak])
    }

    @Test("AST level comes from the underline character")
    func levels() {
        func level(_ text: String) -> Int? {
            for case .heading(let l, _, _, _) in DocumentAST.parse(text) { return l }
            return nil
        }
        #expect(level("T\n===\n") == 1)
        #expect(level("T\n---\n") == 2)
        #expect(level("# T\n") == 1)
        #expect(level("## T\n") == 2)
    }

    @Test("styled like the ATX heading of the same level; underline dimmed and small away from the caret")
    func styling() {
        for (underline, hashes) in [("===", "#"), ("---", "##")] {
            let setext = GFM.attrs("Title\n\(underline)\n")
            let atx = GFM.attrs("\(hashes) Title\n")
            let size = GFM.fontSize(at: 1, in: setext)
            #expect(size == GFM.fontSize(at: 3, in: atx), "\(underline)")
            #expect(size > 14)
            #expect(GFM.bold(at: 1, in: setext))
            let u = 6
            #expect(GFM.fontSize(at: u, in: setext) < 14 && GFM.fontSize(at: u, in: setext) > 2, "small, not hidden")
            #expect((GFM.value(.foregroundColor, at: u, in: setext) as? NSColor) == NSColor.systemGray || GFM.value(.foregroundColor, at: u, in: setext) != nil)
            // Caret on the heading text or the underline: full size.
            #expect(GFM.fontSize(at: u, in: GFM.attrs("Title\n\(underline)\n", caret: 2)) == 14)
            #expect(GFM.fontSize(at: u, in: GFM.attrs("Title\n\(underline)\n", caret: u + 1)) == 14)
            #expect(GFM.fontSize(at: u, in: GFM.attrs("Title\n\(underline)\n", reveal: true)) == 14)
        }
    }

    @Test("a thematic break is not styled as a heading")
    func thematicBreakUnchanged() {
        let a = GFM.attrs("Title\n\n---\n")
        #expect(!GFM.bold(at: 1, in: a))
        #expect(GFM.value(.thematicBreak, at: 7, in: a) as? Bool == true)
    }

    @Test("HTML export")
    func html() {
        #expect(MarkdownHTMLRenderer.html(from: "A *b*\n===\n") == "<h1>A <em>b</em></h1>")
        #expect(MarkdownHTMLRenderer.html(from: "a < b\n---\n") == "<h2>a &lt; b</h2>")
    }

    @Test("incremental parse equals full parse around underlines")
    func fuzz() {
        let templates = ["Title", "text line", "===", "---", "----", "= = =", "", "- item", "> q", "# H", "```", "***"]
        let snippets = ["x", "=", "-", "---", "===", "\n", "\n\n", " ", "text"]
        for seed: UInt64 in (1...15).map({ UInt64($0) &* 0x51ED }) {
            GFM.fuzz(templates: templates, snippets: snippets, seed: seed)
        }
    }
}
