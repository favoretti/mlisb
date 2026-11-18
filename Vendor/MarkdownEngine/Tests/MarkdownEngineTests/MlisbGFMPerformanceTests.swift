//
//  MlisbGFMPerformanceTests.swift
//  MarkdownEngineTests
//
//  mlisb: the new scanners stay linear on hostile text. Each input is sized so a
//  quadratic scan would take minutes; every case must finish in well under a second.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("mlisb GFM scanners stay linear on adversarial input")
struct MlisbGFMPerformanceTests {

    private func rep(_ s: String, _ n: Int) -> String { String(repeating: s, count: n) }

    /// Seconds `body` takes; asserted against `limit`, and printed so the report can quote it.
    @discardableResult
    private func timed(_ label: String, limit: Double = 1.0, _ body: () -> Void) -> Double {
        let start = ContinuousClock.now
        body()
        let d = ContinuousClock.now - start
        let seconds = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        print("PERF \(label): \(String(format: "%.3f", seconds))s")
        #expect(seconds < limit, "\(label) took \(seconds)s")
        return seconds
    }

    /// A registry that resolves labels and footnotes, so the reference scanners run, not just bail out.
    private var withDefinitions: ExtensionRegistry {
        var registry = ExtensionRegistry.empty
        let text = "[a]: /x\n[^a]: note\n"
        registry.references = ReferenceTable(blocks: BlockParser.computeBlocks(text), ns: text as NSString)
        return registry
    }

    // MARK: Inline: brackets, footnotes, links, HTML

    @Test("bracket, footnote, link and tag shapes parse in linear time")
    func inlineShapes() {
        let shapes: [(String, String)] = [
            ("100k [", rep("[", 100_000)),
            ("100k ]", rep("]", 100_000)),
            ("50k nested [[[…]]]", rep("[", 50_000) + rep("]", 50_000)),
            ("50k [a][", rep("[a][", 50_000)),
            ("50k [a][a]", rep("[a][a]", 50_000)),
            ("50k [a][]", rep("[a][]", 50_000)),
            ("50k [a]", rep("[a]", 50_000)),
            ("50k [^", rep("[^", 50_000)),
            ("25k nested [^…]", rep("[^", 25_000) + rep("]", 25_000)),
            ("50k [^a]", rep("[^a]", 50_000)),
            ("50k ![", rep("![", 50_000)),
            ("50k ![a][", rep("![a][", 50_000)),
            ("50k [[", rep("[[", 50_000)),
            ("50k ![[", rep("![[", 50_000)),
            ("50k [a](", rep("[a](", 50_000)),
            ("50k [a](b", rep("[a](b", 50_000)),
            ("50k ![a](", rep("![a](", 50_000)),
            ("one 100k label", "[" + rep("a", 100_000) + "]"),
            ("one 100k footnote id", "[^" + rep("a", 100_000) + "]"),
            ("100k <", rep("<", 100_000)),
            ("50k <b>", rep("<b>", 50_000)),
            ("50k </b>", rep("</b>", 50_000)),
            ("25k <b> then 25k </b>", rep("<b>", 25_000) + rep("</b>", 25_000)),
            ("25k <b><i> then closers", rep("<b><i>", 12_500) + rep("</i></b>", 12_500)),
            ("50k <b>x</b>", rep("<b>x</b>", 50_000)),
            ("30k <a href=\"x\">", rep("<a href=\"x\">", 30_000)),
            ("30k <a href=", rep("<a href=", 30_000)),
            ("30k <b <b", rep("<b <b", 30_000)),
            ("30k <img src=\"a\" ", rep("<img src=\"a\" ", 30_000)),
            ("30k <img src=\"a\">", rep("<img src=\"a\">", 30_000)),
            ("50k <br>", rep("<br>", 50_000)),
            ("one 100k tag name", "<" + rep("a", 100_000)),
            ("one 100k attribute", "<a href=\"" + rep("a", 100_000)),
            ("50k a<b>[a][a]</b>[^a]", rep("a<b>[a][a]</b>[^a]", 50_000)),
            ("20k lines of [a]\\n", rep("[a]\n", 20_000)),
            ("20k lines of <b>\\n", rep("<b>\n", 20_000)),
        ]
        for (label, text) in shapes {
            timed("inline \(label) +refs") { _ = InlineParser.parse(text, registry: withDefinitions) }
            timed("inline \(label)") { _ = InlineParser.parse(text, registry: .empty) }
        }
    }

    // MARK: Blocks

    @Test("block scanners (fences, setext, tables, definitions, HTML blocks, front matter) stay linear")
    func blockShapes() {
        let shapes: [(String, String)] = [
            ("50k ```a openers", rep("```a\n", 50_000)),
            ("50k ~~~ openers growing", (3..<2000).map { rep("~", $0) + "\n" }.joined()),
            ("50k > ```a", rep("> ```a\n", 50_000)),
            ("50k > ``` (pairs)", rep("> ```\n", 50_000)),
            ("50k indented ``` after prose", "text\n" + rep("    ```a\n", 50_000)),
            ("50k list + indented fences", "- a\n" + rep("    ```a\n", 50_000)),
            ("alternating list / fence openers", rep("- a\n    ```a\n", 25_000)),
            ("50k <!--", rep("<!--\n", 50_000)),
            ("50k <!-- x", rep("<!-- x\n", 50_000)),
            ("50k <p align=center>", rep("<p align=\"center\">\n", 50_000)),
            ("50k <div align=left>", rep("<div align=\"left\">\n", 50_000)),
            ("50k <details>", rep("<details>\n", 50_000)),
            ("50k <h1>x</h1>", rep("<h1>x</h1>\n", 50_000)),
            ("50k <summary>", rep("<summary>x\n", 50_000)),
            ("one 100k setext underline", "a\n" + rep("=", 100_000) + "\n"),
            ("one 100k line then ---", rep("a", 100_000) + "\n---\n"),
            ("50k setext headings", rep("a\n---\n", 50_000)),
            ("50k paragraph lines then ===", rep("a\n", 50_000) + "===\n"),
            ("50k ===", rep("===\n", 50_000)),
            ("50k a | b rows then delimiter", rep("a | b\n", 50_000) + "---|---\n"),
            ("25k tables", rep("a | b\n---|---\n1 | 2\n", 25_000)),
            ("one 100k-pipe row", rep("|", 100_000) + "\n---|---\n"),
            ("header 100k cells, 2-col delimiter", rep("a|", 100_000) + "\n---|---\n"),
            ("delimiter 100k cells", "a|b\n" + rep("-|", 100_000) + "\n"),
            ("50k pipe lines", rep("a | b\n", 50_000)),
            ("50k [a]: x", rep("[a]: x\n", 50_000)),
            ("50k [a]: x \"unterminated", rep("[a]: x \"t\n", 50_000)),
            ("50k [^a]: n", rep("[^a]: note\n", 50_000)),
            ("one 100k label line", "[" + rep("a", 100_000) + "]: x\n"),
            ("front matter, no closer, 100k lines", "---\n" + rep("a: b\n", 100_000)),
            ("50k --- after front matter", rep("---\n", 50_000)),
            ("50k alert openers", rep("> [!NOTE]\n", 50_000)),
            ("alert marker with 100k spaces", "> [!NOTE]" + rep(" ", 100_000) + "\n"),
        ]
        for (label, text) in shapes {
            timed("blocks \(label)") { _ = BlockParser.computeBlocks(text) }
        }
    }

    // MARK: Typing

    @Test("typing in the middle of a large mixed document stays incremental")
    func typingStaysIncremental() {
        let section = "# Title\n\nA paragraph with **bold**, `code`, [a][r] and <kbd>k</kbd>.\n\n- item\n- item\n\n"
            + "~~~js\nlet x = 1\n~~~\n\n> [!NOTE]\n> quote\n\na | b\n---|---\n1 | 2\n\n[r]: /x\n\n"
        let doc = rep(section, 1_500)   // ~28k lines
        let state = DocumentParseState()
        _ = state.tokens(for: doc, edit: nil)
        var text = doc as NSString
        var loc = text.length / 2
        // Warm the edit path once, then time 100 keystrokes (a digit in the middle of a paragraph each time).
        func type(_ ch: String) {
            text = text.replacingCharacters(in: NSRange(location: loc, length: 0), with: ch) as NSString
            _ = state.tokens(for: text as String, edit: ParseEditDescriptor(editedRange: NSRange(location: loc, length: ch.utf16.count), delta: ch.utf16.count))
            loc += ch.utf16.count
        }
        // Land inside a paragraph line.
        loc = text.range(of: "A paragraph", options: [], range: NSRange(location: loc, length: text.length - loc)).location + 4
        type("x")
        let seconds = timed("100 keystrokes in a 28k-line document", limit: 3.0) {
            for _ in 0..<100 { type("y") }
        }
        print("PERF per keystroke: \(String(format: "%.1f", seconds * 10)) ms")
    }

    // MARK: Tokens, AST and styling on a few heavy documents

    @Test("styling hostile documents stays linear")
    func stylingShapes() {
        _ = NSApplication.shared
        let shapes: [(String, String)] = [
            ("100k [", rep("[", 100_000)),
            ("50k nested [[[…]]]", rep("[", 50_000) + rep("]", 50_000)),
            ("50k [a][", rep("[a][", 50_000)),
            ("50k [^", rep("[^", 50_000)),
            ("100k <", rep("<", 100_000)),
            ("50k <b>", rep("<b>", 50_000)),
            ("50k [a](", rep("[a](", 50_000)),
            ("20k-line alert", "> [!NOTE]\n" + rep("> line\n", 20_000)),
            ("20k setext headings", rep("Title\n===\n", 20_000)),
            ("20k-row loose table", "a | b\n:--|--:\n" + rep("1 | 2\n", 20_000)),
            ("20k reference uses", rep("[a] and [b][a] and [^a]\n\n", 5_000) + "[a]: /x\n[^a]: note\n"),
            ("20k footnote definitions", rep("[^a]: note\n", 20_000)),
            ("20k html tags", rep("<kbd>k</kbd> <b>b</b> a<br>b\n\n", 5_000)),
            ("5k aligned containers", rep("<p align=\"center\">\ntext\n</p>\n\n", 5_000)),
            ("20k front-matter lines", "---\n" + rep("a: b\n", 20_000) + "---\n"),
            ("5k fenced forms", rep("~~~js\nx\n~~~\n\n- a\n\n    ```\n    y\n    ```\n\n> ```\n> z\n> ```\n\n", 1_700)),
        ]
        for (label, text) in shapes {
            timed("style \(label)", limit: 3.0) {
                _ = MarkdownASTStyler.styleAttributes(text: text, fontName: GFM.fontName, fontSize: 14, configuration: .default)
            }
            timed("tokens \(label)", limit: 3.0) { _ = MarkdownTokenizer.parseTokensViaAST(in: text) }
            timed("html \(label)", limit: 3.0) { _ = MarkdownHTMLRenderer.html(from: text) }
        }
    }
}
