//
//  MlisbGFMFenceTests.swift
//  MarkdownEngineTests
//
//  mlisb: fenced code blocks — ~~~, long fences, indented, in lists and quotes.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("mlisb GFM fenced code")
struct MlisbGFMFenceTests {

    private func code(_ text: String) -> [String] {
        let ns = text as NSString
        return GFM.tokens(text).filter { $0.kind == .codeBlock }.map { MarkdownTokenizer.codeText(of: $0, in: ns) }
    }

    @Test("every valid fence form is a code block with its code stripped of prefixes")
    func forms() {
        let cases: [(String, String)] = [
            ("```\nx\n```\n", "x\n"),
            ("~~~\nx\n~~~\n", "x\n"),
            ("````\n```\nx\n````\n", "```\nx\n"),                // closer must be as long
            ("~~~~\nx\n~~~~~~\n", "x\n"),                        // longer closer is fine
            ("   ```js\n   x\n  y\n   ```\n", "x\ny\n"),          // indent stripped up to the opener's
            ("- item\n\n    ```js\n    x\n    ```\n", "x\n"),     // under a list item
            ("1. item\n   ```\n   x\n   ```\n", "x\n"),
            ("- a\n  - b\n\n      ~~~\n      x\n      ~~~\n", "x\n"),
            ("> ```js\n> let x\n> ```\n", "let x\n"),
            ("> ~~~\n>   y\n> ~~~\n", "  y\n"),
        ]
        for (text, expected) in cases {
            #expect(code(text) == [expected], "\(text.debugDescription)")
            #expect(GFM.kinds(text).contains(.fencedCode), "\(text.debugDescription)")
        }
    }

    @Test("invalid forms stay ordinary text")
    func invalid() {
        let cases = [
            "```js\nno closer\n",                 // unclosed: deliberate difference from the spec
            "~~~\nx\n```\n",                      // mismatched character
            "````\nx\n```\n",                     // closer too short
            "text\n\n    ```\n    x\n    ```\n",   // indented code, not a fence, outside a list
            "``` a`b\nx\n```\n",                  // backtick info string with a backtick
            "> ```\n> x\nplain\n> ```\n",          // quote ends before the closer
        ]
        for text in cases {
            #expect(!GFM.kinds(text).contains(.fencedCode), "\(text.debugDescription)")
            #expect(code(text).isEmpty, "\(text.debugDescription)")
        }
    }

    @Test("a fence inside a quote splits the quote around it")
    func quoteSplit() {
        #expect(GFM.kinds("> a\n> ```\n> x\n> ```\n> b\n") == [.blockquote, .fencedCode, .blockquote])
    }

    @Test("the text is styled as code, fences hide away from the caret and show inside it")
    func styling() {
        let forms = ["~~~js\nlet x\n~~~\n", "````\nlet x\n````\n", "  ```js\n  let x\n  ```\n",
                     "- a\n\n    ```js\n    let x\n    ```\n", "> ```js\n> let x\n> ```\n"]
        for text in forms {
            let ns = text as NSString
            let x = ns.range(of: "let x").location
            let open = ns.rangeOfCharacter(from: CharacterSet(charactersIn: "`~")).location
            let away = GFM.attrs(text)
            #expect(GFM.value(.backgroundColor, at: x, in: away) != nil, "\(text.debugDescription)")
            #expect(GFM.isHidden(open, in: away), "\(text.debugDescription)")
            let inside = GFM.attrs(text, caret: x)
            #expect(!GFM.isHidden(open, in: inside), "\(text.debugDescription)")
            #expect(!GFM.isHidden(open, in: GFM.attrs(text, reveal: true)), "\(text.debugDescription)")
        }
    }

    @Test("indentation of a code line collapses away from the caret")
    func prefixCollapses() {
        let text = "> ```\n> let x\n> ```\n"
        let at = (text as NSString).range(of: "> let").location
        #expect(GFM.fontSize(at: at, in: GFM.attrs(text)) < 2)
        #expect(GFM.fontSize(at: at, in: GFM.attrs(text, caret: at + 3)) > 5)
    }

    private struct Highlight: SyntaxHighlighter {
        var appearanceDidChangeNotification: Notification.Name? { nil }
        func codeFont(size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
        func backgroundColor() -> NSColor { .gray }
        func highlight(code: String, language: String?) -> NSAttributedString? {
            let out = NSMutableAttributedString(string: code)
            let r = (code as NSString).range(of: "y")
            if r.location != NSNotFound { out.addAttribute(.foregroundColor, value: NSColor.red, range: r) }
            return out
        }
    }

    @Test("highlight colours land on the right characters when prefixes were stripped")
    func highlightMapsBack() {
        let text = "> ```swift\n> x\n> y\n> ```\n"
        let y = (text as NSString).range(of: "y").location
        let a = GFM.attrs(text) { $0.services.syntaxHighlighter = Highlight() }
        #expect((GFM.value(.foregroundColor, at: y, in: a) as? NSColor) == .red)
        #expect((GFM.value(.foregroundColor, at: y - 4, in: a) as? NSColor) != .red)   // the `x`
    }

    private struct Diagram: DiagramRenderer {
        func image(language: String, source: String) -> NSImage? {
            language == "mermaid" && source.contains("A-->B") ? NSImage(size: NSSize(width: 40, height: 20)) : nil
        }
        func fingerprint() -> AnyHashable { 0 }
    }

    @Test("diagram fences draw as an image in every fence form")
    func diagrams() {
        let services = MarkdownEditorServices(diagrams: Diagram())
        let forms = ["```mermaid\nA-->B\n```\n", "~~~mermaid\nA-->B\n~~~\n", "````mermaid\nA-->B\n````\n",
                     "  ```mermaid\n  A-->B\n  ```\n", "- a\n\n    ```mermaid\n    A-->B\n    ```\n",
                     "> ```mermaid\n> A-->B\n> ```\n"]
        for text in forms {
            let a = GFM.fullAttrs(text, services: services)
            #expect(a.contains { $0.attributes[.latexImage] != nil }, "\(text.debugDescription)")
            // Source shown while the caret is inside.
            let inside = GFM.fullAttrs(text, caret: (text as NSString).range(of: "A-->B").location, services: services)
            #expect(!inside.contains { $0.attributes[.latexImage] != nil }, "\(text.debugDescription)")
        }
        #expect(!GFM.fullAttrs("```mermaid\nother\n```\n", services: services).contains { $0.attributes[.latexImage] != nil })
    }

    @Test("HTML export strips prefixes, escapes and keeps the language")
    func html() {
        #expect(MarkdownHTMLRenderer.html(from: "~~~js title=x\na < b\n~~~\n")
                == "<pre><code class=\"language-js\">a &lt; b</code></pre>")
        #expect(MarkdownHTMLRenderer.html(from: "- a\n\n    ```\n    x\n    ```\n").contains("<pre><code>x</code></pre>"))
        #expect(MarkdownHTMLRenderer.html(from: "> ```\n> q\n> ```\n").contains("<pre><code>q</code></pre>"))
    }

    @Test("rendering never modifies the text")
    func textUntouched() {
        let text = "- a\n\n    ~~~js\n    x\n    ~~~\n"
        let tv = NativeTextView(frame: .zero)
        let c = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil)
        c.rebuildTextStorageAndStyle(tv, from: text)
        #expect(tv.string == text)
    }

    @Test("incremental parse equals full parse over fence forms")
    func fuzz() {
        let templates = ["```swift", "~~~", "~~~~", "````", "```", "> ```js", "> x", "    ```", "   ~~~", "- item",
                         "  - nested", "    code", "1. one", "plain text", "", "# H", "> quote"]
        let snippets = ["x", " ", "    ", "\n", "`", "```", "~~~", "> ", "- ", "\n\n", "~", "\n> ```\n"]
        for seed: UInt64 in (1...20).map({ UInt64($0) &* 0x9E37 }) { GFM.fuzz(templates: templates, snippets: snippets, seed: seed) }
    }
}
