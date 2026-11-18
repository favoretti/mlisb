//
//  MlisbGFMFrontMatterTests.swift
//  MarkdownEngineTests
//
//  mlisb: front matter at the very start of the document.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("mlisb GFM front matter")
struct MlisbGFMFrontMatterTests {

    @Test("only a --- block that starts the document is front matter")
    func blocks() {
        #expect(GFM.kinds("---\ntitle: x\n---\n# H\n") == [.frontMatter, .heading])
        #expect(GFM.kinds("---\n- a\n# not a heading\n---\ntext\n") == [.frontMatter, .paragraph])
        #expect(GFM.kinds("\n---\ntitle: x\n---\n") == [.thematicBreak, .setextHeading])   // not at the start
        #expect(GFM.kinds("text\n\n---\na\n---\n") == [.paragraph, .thematicBreak, .setextHeading])
        #expect(GFM.kinds("---\nno closer\n") == [.thematicBreak, .paragraph])
        #expect(GFM.kinds("--- \na\n---  \n") == [.frontMatter])
        #expect(GFM.kinds("----\na\n---\n") != [.frontMatter])
        #expect(GFM.kinds("---\n---\n") == [.frontMatter])
    }

    @Test("monospaced and dimmed, with no heading, list, rule or emphasis styling inside")
    func styling() {
        let text = "---\n# title\n- item\n**bold** [x]\n---\n\n# Real\n"
        let ns = text as NSString
        let a = GFM.attrs(text)
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName
        for needle in ["title", "item", "bold"] {
            let at = ns.range(of: needle).location
            let font = GFM.value(.font, at: at, in: a) as? NSFont
            #expect(font?.isFixedPitch == true, "\(needle) \(mono)")
            #expect(!GFM.bold(at: at, in: a), "\(needle)")
            #expect(GFM.value(.foregroundColor, at: at, in: a) as? NSColor == NSColor.secondaryLabelColor, "\(needle)")
            #expect(GFM.value(.bulletMarker, at: at - 2, in: a) == nil)
            #expect(GFM.value(.backgroundColor, at: at, in: a) == nil)
        }
        #expect(GFM.value(.thematicBreak, at: 0, in: a) == nil)
        #expect(GFM.value(.thematicBreak, at: ns.range(of: "---\n\n").location, in: a) == nil)
        // The first `[x]` text is not recoloured as an incomplete link, and the heading after it is a heading.
        #expect(GFM.fontSize(at: ns.range(of: "Real").location, in: a) > 14)
        // Source is always shown: caret inside or source mode change nothing about visibility.
        for variant in [GFM.attrs(text, caret: 6), GFM.attrs(text, reveal: true)] {
            #expect(!GFM.isHidden(0, in: variant))
            #expect(GFM.fontSize(at: ns.range(of: "bold").location, in: variant) > 5)
        }
    }

    @Test("HTML export keeps the metadata, escaped")
    func html() {
        #expect(MarkdownHTMLRenderer.html(from: "---\na: <b>\n---\n# H\n")
                == "<pre class=\"front-matter\"><code>a: &lt;b&gt;</code></pre>\n<h1>H</h1>")
    }

    @Test("incremental parse equals full parse around front matter")
    func fuzz() {
        let templates = ["---", "---", "title: x", "- a", "# H", "text", "", "***", "----", "> q", "```"]
        let snippets = ["---", "-", "x", "\n", "\n---\n", " ", "# "]
        for seed: UInt64 in (1...20).map({ UInt64($0) &* 0xFA11 }) {
            GFM.fuzz(templates: templates, snippets: snippets, seed: seed)
        }
    }
}
