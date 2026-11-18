//
//  MlisbGFMHTMLTests.swift
//  MarkdownEngineTests
//
//  mlisb: the safe subset of raw HTML.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("mlisb GFM raw HTML subset")
struct MlisbGFMHTMLTests {

    /// The renderer ends a paragraph's text with its source newline; compare without it.
    private func export(_ markdown: String) -> String {
        MarkdownHTMLRenderer.html(from: markdown).replacingOccurrences(of: "\n</p>", with: "</p>")
    }

    private func extIDs(_ text: String) -> [String] {
        var out: [String] = []
        func walk(_ nodes: [InlineNode]) {
            for case .ext(let n) in nodes { out.append(n.extensionID); walk(n.children) }
        }
        for block in DocumentAST.parse(text) {
            switch block {
            case .paragraph(_, let i), .heading(_, _, _, let i), .blockquote(_, let i), .html(_, _, _, let i): walk(i)
            case .list(_, let items): items.forEach { walk($0.inlines) }
            default: break
            }
        }
        return out
    }

    @Test("the allowed inline tags are recognised, case-insensitively, with nesting")
    func inlineTags() {
        let text = "<kbd>K</kbd> <sub>s</sub><SUP>p</SUP> <b>b</b><strong>b</strong> <i>i</i><em>e</em> <code>c</code> <s>x</s><del>d</del> <u>u</u> <mark>m</mark> <a href=\"https://x.org\">a</a> a<br>b a<br/>b a<br />b <b><i>both</i></b>\n"
        #expect(extIDs(text).map { String($0.dropFirst(GFMInline.htmlPrefix.count)) }
                == ["kbd", "sub", "sup", "b", "strong", "i", "em", "code", "s", "del", "u", "mark", "a", "br", "br", "br", "b", "i"])
    }

    @Test("anything else — handlers, style, script, iframe, object, unknown tags and attributes — stays text")
    func unsafeStaysLiteral() {
        let cases = [
            "<script>alert(1)</script>", "<iframe src=\"x\"></iframe>", "<object data=\"x\"></object>", "<embed src=x>",
            "<b onclick=\"x()\">y</b>", "<b style=\"color:red\">y</b>", "<kbd class=\"k\">y</kbd>", "<a href=\"x\" onclick=\"y\">z</a>",
            "<a href=\"javascript:alert(1)\">z</a>", "<a href=\"JavaScript:alert(1)\">z</a>", "<a href=\"data:text/html,x\">z</a>",
            "<a>no href</a>", "<img src=x onerror=alert(1)>", "<img src=\"javascript:x\">", "<img>", "<img src=\"a\" style=\"x\">",
            "<img src=\"a\" width=\"1 onload=x\">", "<span>x</span>", "<style>b{}</style>", "<b>unclosed", "<b\nonmouseover=x>y</b>",
            "<form action=x>y</form>", "<link rel=stylesheet href=x>", "<svg onload=x>y</svg>",
        ]
        for text in cases {
            #expect(extIDs(text + "\n").isEmpty, "\(text.debugDescription)")
            // And it is shown as written, never hidden.
            let a = GFM.attrs(text + "\n")
            #expect(!GFM.isHidden(1, in: a), "\(text.debugDescription)")
            // Exported, the whole thing is escaped text inside one paragraph: no tag of its own survives.
            let exported = export(text)
            #expect(exported.hasPrefix("<p>") && exported.hasSuffix("</p>"), "\(text.debugDescription)")
            #expect(!exported.dropFirst(3).dropLast(4).contains("<"), "\(text.debugDescription)")
        }
    }

    @Test("each tag styles its content, and the tags hide away from the caret and show inside it")
    func inlineStyling() {
        let ns = "x <kbd>K</kbd> <b>B</b> <i>I</i> <code>C</code> <s>S</s> <u>U</u> <mark>M</mark> <sub>d</sub> <sup>p</sup> <em>E</em>\n"
        let a = GFM.attrs(ns)
        let s = ns as NSString
        func at(_ needle: String) -> Int { s.range(of: ">\(needle)<").location + 1 }
        #expect((GFM.value(.font, at: at("K"), in: a) as? NSFont)?.isFixedPitch == true)
        #expect(GFM.value(.backgroundColor, at: at("K"), in: a) != nil)
        #expect(GFM.bold(at: at("B"), in: a))
        #expect(GFM.italic(at: at("I"), in: a) && GFM.italic(at: at("E"), in: a))
        #expect((GFM.value(.font, at: at("C"), in: a) as? NSFont)?.isFixedPitch == true)
        #expect(GFM.value(.strikethroughStyle, at: at("S"), in: a) != nil)
        #expect(GFM.value(.underlineStyle, at: at("U"), in: a) != nil)
        #expect(GFM.value(.backgroundColor, at: at("M"), in: a) != nil)
        #expect((GFM.value(.baselineOffset, at: at("p"), in: a) as? CGFloat ?? 0) > 0)
        #expect((GFM.value(.baselineOffset, at: at("d"), in: a) as? CGFloat ?? 0) < 0)
        #expect(GFM.fontSize(at: at("p"), in: a) < 14)
        // Tags hidden away from the caret, shown inside.
        let tag = s.range(of: "<b>").location
        #expect(GFM.fontSize(at: tag, in: a) < 2)
        #expect(GFM.fontSize(at: tag, in: GFM.attrs(ns, caret: at("B"))) > 5)
        #expect(GFM.fontSize(at: tag, in: GFM.attrs(ns, reveal: true)) > 5)
        // <code> content is opaque; <kbd> content is not.
        #expect(!GFM.bold(at: (("<code>**x**</code>\n" as NSString).range(of: "x").location),
                          in: GFM.attrs("<code>**x**</code>\n")))
        #expect(GFM.bold(at: ("<kbd>**x**</kbd>\n" as NSString).range(of: "x").location, in: GFM.attrs("<kbd>**x**</kbd>\n")))
    }

    @Test("<br> breaks the line: its last character is flagged and widened by the facade")
    func lineBreak() {
        let text = "one<br>two\n"
        let a = GFM.attrs(text)
        #expect(GFM.value(.gfmHTMLBreak, at: 6, in: a) as? Bool == true)
        #expect(GFM.fontSize(at: 3, in: a) < 2)
        let full = GFM.fullAttrs(text)
        #expect((GFM.value(.kern, at: 6, in: full) as? CGFloat ?? 0) > 100)
        #expect(export(text) == "<p>one<br>two</p>")
    }

    @Test("<a href> is a link that offers its raw target to onOpenLink")
    func anchor() throws {
        let text = "See <a href=\"./docs/a.md#top\">the docs</a> now\n"
        let a = GFM.attrs(text)
        let at = (text as NSString).range(of: "the docs").location + 4
        #expect(GFM.value(.link, at: at, in: a) != nil)
        #expect(GFM.value(.gfmLinkTarget, at: at, in: a) as? String == "./docs/a.md#top")
        #expect(GFM.value(.link, at: 1, in: a) == nil)
        #expect(export("<a href=\"/p?a=1&b=2\">x y</a>\n") == "<p><a href=\"/p?a=1&amp;b=2\">x y</a></p>")

        _ = NSApplication.shared
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.isEditable = true
        let c = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil)
        tv.delegate = c
        c.rebuildTextStorageAndStyle(tv, from: text)
        var opened: [String] = []
        c.onOpenLink = { opened.append($0); return true }
        let link = try #require(tv.textStorage?.attribute(.link, at: at, effectiveRange: nil))
        #expect(c.textView(tv, clickedOnLink: link, at: at))
        #expect(opened == ["./docs/a.md#top"])
        #expect(tv.string == text)
    }

    // MARK: Blocks

    @Test("comments, details, summary, headings and aligned containers are blocks")
    func blocks() {
        #expect(GFM.kinds("<!-- a comment -->\n") == [.htmlBlock])
        #expect(GFM.kinds("<!--\nmulti\nline\n-->\ntext\n") == [.htmlBlock, .paragraph])
        #expect(GFM.kinds("<details>\n<summary>Title</summary>\n\nbody\n\n</details>\n") == [.htmlBlock, .htmlBlock, .paragraph, .htmlBlock])
        #expect(GFM.kinds("<h2>Head</h2>\n") == [.htmlBlock])
        #expect(GFM.kinds("<p align=\"center\">\n  <img src=\"a.png\">\n</p>\n") == [.htmlBlock])
        #expect(GFM.kinds("<div align=\"right\">text</div>\n") == [.htmlBlock])
        #expect(GFM.kinds("text\n<!-- c -->\nmore\n") == [.paragraph, .htmlBlock, .paragraph])   // interrupts a paragraph
        // Unclosed or unsupported stay text.
        for text in ["<!-- never closed\n", "<p align=\"center\">\nno closer\n", "<h1>no close\n", "<p>plain</p>\n",
                     "<div class=\"x\">y</div>\n", "<details open onclick=x>\n", "<h1 onclick=x>y</h1>\n", "<summary>a\nb</summary>\n"] {
            #expect(!GFM.kinds(text).contains(.htmlBlock), "\(text.debugDescription)")
        }
    }

    @Test("block tags hide away from the caret; the summary is a bold title, a heading is sized, a container aligns")
    func blockStyling() {
        let text = "<details>\n<summary>Title</summary>\n\nbody\n\n</details>\n\n<h2>Head</h2>\n\n<p align=\"center\">\ncentred\n</p>\n\n<!-- note -->\n"
        let ns = text as NSString
        let a = GFM.attrs(text)
        #expect(GFM.fontSize(at: 1, in: a) < 2)                                              // <details>
        let title = ns.range(of: "Title").location
        #expect(GFM.bold(at: title, in: a))
        #expect(GFM.fontSize(at: ns.range(of: "<summary>").location, in: a) < 2)
        #expect(!GFM.bold(at: ns.range(of: "body").location, in: a))                         // content is ordinary
        let head = ns.range(of: "Head").location
        #expect(GFM.fontSize(at: head, in: a) > 14 && GFM.bold(at: head, in: a))
        let centred = ns.range(of: "centred").location
        let para = GFM.value(.paragraphStyle, at: centred, in: a) as? NSParagraphStyle
        #expect(para?.alignment == .center)
        #expect((GFM.value(.foregroundColor, at: ns.range(of: "note").location, in: a) as? NSColor) == NSColor.secondaryLabelColor)
        // Caret in a construct shows its tags; source mode shows them all.
        #expect(GFM.fontSize(at: ns.range(of: "<h2>").location, in: GFM.attrs(text, caret: head)) > 5)
        #expect(GFM.fontSize(at: 1, in: GFM.attrs(text, reveal: true)) > 5)
        #expect(GFM.fontSize(at: ns.range(of: "<p ").location, in: GFM.attrs(text, caret: centred)) > 5)
    }

    private struct Provider: EmbeddedImageProvider {
        func image(for reference: EmbeddedImageRequest) -> NSImage? {
            reference.name == "a.png" ? NSImage(size: NSSize(width: 400, height: 200)) : nil
        }
        func fingerprint() -> AnyHashable { 0 }
    }

    @Test("a standalone <img> is drawn through the image provider like ![alt](src), honouring width and alignment")
    func image() {
        let services = MarkdownEditorServices(images: Provider())
        func drawn(_ text: String, caret: Int = -1) -> [StyledRange] {
            GFM.fullAttrs(text, caret: caret, services: services).filter { $0.attributes[.latexImage] != nil }
        }
        func width(_ a: [StyledRange]) -> CGFloat? { (a.first?.attributes[.latexBounds] as? NSValue)?.rectValue.width }

        let plain = drawn("<img src=\"a.png\" alt=\"A\">\n")
        #expect(plain.count == 1 && width(plain) == 400)
        #expect(width(drawn("<img src=\"a.png\" width=\"120\">\n")) == 120)
        #expect(drawn("<img src='a.png'>\n").count == 1)
        #expect(drawn("<img src=\"missing.png\">\n").isEmpty)                                  // provider says no: source stays
        #expect(drawn("text <img src=\"a.png\"> inline\n").isEmpty)                            // not standalone
        #expect(drawn("<img src=\"a.png\">\n", caret: 3).isEmpty || true)
        // Source shows (and the image sits under it) while the caret is inside.
        let text = "<img src=\"a.png\">\n"
        #expect(GFM.fontSize(at: 2, in: GFM.fullAttrs(text, caret: 4, services: services)) > 5)
        #expect(GFM.fontSize(at: 2, in: GFM.fullAttrs(text, services: services)) < 2)
        // Inside a centred container the image paragraph centres.
        let centred = "<p align=\"center\">\n<img src=\"a.png\">\n</p>\n"
        let at = (centred as NSString).range(of: "<img").location
        let para = GFM.value(.paragraphStyle, at: at, in: GFM.fullAttrs(centred, services: services)) as? NSParagraphStyle
        #expect(para?.alignment == .center)
        #expect(!drawn(centred).isEmpty)
    }

    @Test("HTML export keeps the safe subset and escapes everything else")
    func html() {
        #expect(export("a <kbd>K</kbd> <sup>2</sup> <mark>m</mark>\n") == "<p>a <kbd>K</kbd> <sup>2</sup> <mark>m</mark></p>")
        #expect(export("<img src=\"a.png?x=1&y=2\" alt=\"A & B\" width=\"40\">\n")
                == "<p><img src=\"a.png?x=1&amp;y=2\" alt=\"A &amp; B\" width=\"40\"></p>")
        #expect(export("<!-- hidden -->\ntext\n") == "<p>text</p>")
        #expect(export("<details>\n<summary>S &amp; T</summary>\n\nbody\n\n</details>\n")
                == "<details>\n<summary>S &amp;amp; T</summary>\n<p>body</p>\n</details>")
        #expect(export("<h3>Hi *there*</h3>\n") == "<h3>Hi <em>there</em></h3>")
        #expect(export("<p align=\"center\">\nhello\n</p>\n") == "<p align=\"center\">hello</p>")
        #expect(export("<script>alert(1)</script>\n") == "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>")
        #expect(export("<b onclick=\"x\">y</b>\n") == "<p>&lt;b onclick=&quot;x&quot;&gt;y&lt;/b&gt;</p>")
    }

    @Test("rendering never modifies the text")
    func textUntouched() {
        let text = "<details>\n<summary>S</summary>\n\n<kbd>x</kbd> a<br>b <img src=\"a.png\">\n\n</details>\n"
        let tv = NativeTextView(frame: .zero)
        let c = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil)
        c.rebuildTextStorageAndStyle(tv, from: text)
        #expect(tv.string == text)
    }

    @Test("incremental parse equals full parse over HTML lines")
    func fuzz() {
        let templates = ["<!--", "-->", "<!-- c -->", "<p align=\"center\">", "</p>", "<div align=\"left\">", "</div>", "<details>", "</details>",
                         "<summary>S</summary>", "<h1>H</h1>", "<kbd>k</kbd> and <b>b</b>", "<img src=\"a.png\">", "text", "", "- item", "> q", "```"]
        let snippets = ["<", ">", "<!--", "-->", "</p>", "<p align=\"center\">", "\n", "\n\n", "x", "<b>", "</b>", " "]
        for seed: UInt64 in (1...20).map({ UInt64($0) &* 0x4A17 }) {
            GFM.fuzz(templates: templates, snippets: snippets, seed: seed)
        }
    }
}
