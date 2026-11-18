//
//  MlisbGFMReferenceTests.swift
//  MarkdownEngineTests
//
//  mlisb: reference-style links / images and footnotes.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("mlisb GFM references and footnotes")
struct MlisbGFMReferenceTests {

    private let doc = "A [text][Label], [label][], [LABEL] and ![alt][label]; [nope][x] and [undefined].\n\n[label]: https://x.org \"Title\"\n"

    private func extNodes(_ text: String) -> [ExtensionInlineNode] {
        var out: [ExtensionInlineNode] = []
        func walk(_ nodes: [InlineNode]) {
            for case .ext(let n) in nodes { out.append(n); walk(n.children) }
        }
        for block in DocumentAST.parse(text) {
            switch block {
            case .paragraph(_, let i), .heading(_, _, _, let i), .blockquote(_, let i), .footnoteDefinition(_, _, let i): walk(i)
            case .list(_, let items): items.forEach { walk($0.inlines) }
            default: break
            }
        }
        return out
    }

    @Test("definition lines are their own blocks, but never interrupt a paragraph")
    func definitionBlocks() {
        #expect(GFM.kinds("[a]: http://x \"T\"\n") == [.linkDefinition])
        #expect(GFM.kinds("  [a]: <http://x y> 'T'\n[b]: /p (T)\n") == [.linkDefinition, .linkDefinition])
        #expect(GFM.kinds("[^1]: a *note*\n") == [.footnoteDefinition])
        #expect(GFM.kinds("text\n[a]: http://x\n") == [.paragraph])
        for bad in ["[a]:\n", "[a] http://x\n", "[a]: x \"unterminated\n", "[]: x\n", "    [a]: x\n", "[a]: x y\n"] {
            #expect(!GFM.kinds(bad).contains(.linkDefinition), "\(bad.debugDescription)")
        }
    }

    @Test("full, collapsed, shortcut and image references resolve case-insensitively; undefined labels stay text")
    func resolution() {
        let nodes = extNodes(doc)
        #expect(nodes.map(\.extensionID) == [GFMInline.refID, GFMInline.refID, GFMInline.refID, GFMInline.refImageID])
        #expect(nodes.allSatisfy { $0.target == "https://x.org" })
        let ns = doc as NSString
        #expect(ns.substring(with: nodes[0].range) == "[text][Label]")
        #expect(ns.substring(with: nodes[0].contentRange) == "text")
        #expect(ns.substring(with: nodes[1].range) == "[label][]")
        #expect(ns.substring(with: nodes[2].range) == "[LABEL]")
        #expect(ns.substring(with: nodes[3].range) == "![alt][label]")
        // No definitions: nothing resolves.
        #expect(extNodes("A [text][label] and [label].\n").isEmpty)
        // Inline links keep winning, and the first definition of a label wins.
        #expect(extNodes("[a](http://y) [a]\n\n[a]: http://one\n[a]: http://two\n").map(\.target) == ["http://one"])
    }

    @Test("a reference link looks like an inline link and offers the definition's target")
    func styling() {
        let a = GFM.attrs(doc)
        let ns = doc as NSString
        let t = ns.range(of: "text][").location
        #expect(GFM.value(.link, at: t, in: a) != nil)
        #expect(GFM.value(.underlineStyle, at: t, in: a) != nil)
        #expect(GFM.value(.gfmLinkTarget, at: t, in: a) as? String == "https://x.org")
        // The incomplete-link bracket pass must not repaint it.
        #expect((GFM.value(.foregroundColor, at: t, in: a) as? NSColor) == NSColor.linkColor)
        // The `][Label]` syntax is hidden away from the caret and shown inside.
        let syntax = ns.range(of: "][Label]").location
        #expect(GFM.fontSize(at: syntax, in: a) < 2)
        #expect(GFM.fontSize(at: syntax, in: GFM.attrs(doc, caret: t)) > 5)
        #expect(GFM.fontSize(at: syntax, in: GFM.attrs(doc, reveal: true)) > 5)
        // Undefined labels are plain text; the definition line is dimmed.
        let undefined = ns.range(of: "undefined").location
        #expect(GFM.value(.link, at: undefined, in: a) == nil)
        #expect(GFM.value(.link, at: ns.range(of: "nope").location, in: a) == nil)
        #expect((GFM.value(.foregroundColor, at: ns.range(of: "https").location, in: a) as? NSColor) == NSColor.secondaryLabelColor)
        #expect((GFM.value(.foregroundColor, at: ns.range(of: "[label]:").location, in: a) as? NSColor) == NSColor.secondaryLabelColor)
        // Emphasis inside the label still applies.
        let emph = "[**bold**][l]\n\n[l]: /p\n"
        #expect(GFM.bold(at: (emph as NSString).range(of: "bold").location, in: GFM.attrs(emph)))
    }

    @Test("editing a definition changes its uses, and the coordinator restyles the whole document for it")
    func definitionEdits() {
        func target(_ text: String) -> String? {
            GFM.value(.gfmLinkTarget, at: (text as NSString).range(of: "use").location + 1, in: GFM.attrs(text)) as? String
        }
        #expect(target("[use]\n\n[use]: /one\n") == "/one")
        #expect(target("[use]\n\n[use]: /two\n") == "/two")
        #expect(target("[use]\n\n[usé]: /two\n") == nil)
        let c = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil)
        let text = "[use]\n\n[use]: /one\nplain\n" as NSString
        #expect(c.editWindowTouchesExtensionFence(in: text, around: NSRange(location: 14, length: 1)))
        #expect(!c.editWindowTouchesExtensionFence(in: text, around: NSRange(location: 2, length: 1)))
        #expect(!c.editWindowTouchesExtensionFence(in: text, around: NSRange(location: 21, length: 1)))
    }

    @Test("footnote references are small raised markers; a definition marker is dimmed; undefined ids stay text")
    func footnoteStyling() {
        let text = "Claim[^1] and [^2] and [^note].\n\n[^1]: The *note*.\n[^note]: Long id.\n"
        let ns = text as NSString
        let a = GFM.attrs(text)
        let one = ns.range(of: "^1").location + 1
        #expect(GFM.fontSize(at: one, in: a) < 14 && GFM.fontSize(at: one, in: a) > 5)
        #expect((GFM.value(.baselineOffset, at: one, in: a) as? CGFloat ?? 0) > 0)
        #expect(GFM.value(.gfmFootnoteID, at: one, in: a) as? String == "1")
        #expect(GFM.value(.link, at: one, in: a) != nil)
        #expect(GFM.fontSize(at: ns.range(of: "[^1]").location, in: a) < 2)               // brackets hidden
        #expect(GFM.fontSize(at: ns.range(of: "[^1]").location, in: GFM.attrs(text, caret: one)) > 5)
        #expect(GFM.value(.gfmFootnoteID, at: ns.range(of: "^2").location + 1, in: a) == nil)   // undefined
        let def = ns.range(of: "[^1]: ").location
        #expect((GFM.value(.foregroundColor, at: def, in: a) as? NSColor) == NSColor.secondaryLabelColor)
        #expect(GFM.value(.gfmFootnoteID, at: def + 2, in: a) == nil)
        #expect(GFM.italic(at: ns.range(of: "note*").location, in: a))                  // definition text is inline-styled
    }

    private func stage(_ text: String) -> (NativeTextView, NativeTextViewCoordinator) {
        _ = NSApplication.shared
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.isEditable = true
        let c = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil)
        tv.delegate = c
        c.rebuildTextStorageAndStyle(tv, from: text)
        return (tv, c)
    }

    @Test("clicking a footnote reference moves the caret to its definition; the text is untouched")
    func footnoteClick() throws {
        let text = "Claim[^1].\n\n[^1]: The note.\n"
        let (tv, c) = stage(text)
        let at = (text as NSString).range(of: "^1").location + 1
        let link = try #require(tv.textStorage?.attribute(.link, at: at, effectiveRange: nil))
        #expect(c.textView(tv, clickedOnLink: link, at: at))
        #expect(tv.selectedRange() == NSRange(location: (text as NSString).range(of: "The note").location, length: 0))
        #expect(tv.string == text)
    }

    @Test("clicking a reference link offers the definition's target to onOpenLink")
    func referenceClick() throws {
        let text = "See [the docs][d] and [d].\n\n[d]: ./docs/index.md \"Docs\"\n"
        let (tv, c) = stage(text)
        var opened: [String] = []
        c.onOpenLink = { opened.append($0); return true }
        for needle in ["the docs", "[d]."] {
            let at = (text as NSString).range(of: needle).location + (needle.hasPrefix("[") ? 1 : 2)
            let link = try #require(tv.textStorage?.attribute(.link, at: at, effectiveRange: nil))
            #expect(c.textView(tv, clickedOnLink: link, at: at))
        }
        #expect(opened == ["./docs/index.md", "./docs/index.md"])
        #expect(tv.string == text)
    }

    @Test("HTML export resolves references and footnotes and escapes text")
    func html() {
        let md = "[a <b>][x] ![i][x] and [^f]\n\n[x]: /p?q=1&r=2\n[^f]: n < m\n"
        let out = MarkdownHTMLRenderer.html(from: md)
        #expect(out.contains("<a href=\"/p?q=1&amp;r=2\">a &lt;b&gt;</a>"))
        #expect(out.contains("<img src=\"/p?q=1&amp;r=2\" alt=\"i\">"))
        #expect(out.contains("<sup class=\"footnote-ref\"><a href=\"#fn-f\">f</a></sup>"))
        #expect(out.contains("<div class=\"footnote-definition\" id=\"fn-f\"><sup>f</sup> n &lt; m</div>"))
        #expect(!out.contains("[x]:"))
    }

    @Test("incremental parse equals full parse over definitions and uses")
    func fuzz() {
        let templates = ["[a]: /one", "[b]: /two \"T\"", "[^1]: note", "use [a] and [b][a] and [^1]", "text", "", "# H",
                         "- [a]", "> [a][]", "[a", "![x][b]"]
        let snippets = ["[", "]", "[a]", ": /x", "\n", "\n\n", "[^1]", "x", " "]
        for seed: UInt64 in (1...15).map({ UInt64($0) &* 0x2EF }) {
            GFM.fuzz(templates: templates, snippets: snippets, seed: seed)
        }
    }
}
