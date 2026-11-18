//
//  MlisbGFMTableTests.swift
//  MarkdownEngineTests
//
//  mlisb: tables without outer pipes.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("mlisb GFM tables without outer pipes")
struct MlisbGFMTableTests {

    @Test("a row, a delimiter row and body rows make a table with or without outer pipes")
    func blocks() {
        #expect(GFM.kinds("a | b\n---|---\n1 | 2\n3 | 4\n") == [.table])
        #expect(GFM.kinds("a | b\n:--|--:\n1 | 2\n") == [.table])
        #expect(GFM.kinds("| a | b |\n|---|---|\n| 1 | 2 |\n") == [.table])
        #expect(GFM.kinds("| a | b |\n---|---\n1 | 2\n") == [.table])
        #expect(GFM.kinds("a | b\n|---|---|\n") == [.table])
        #expect(GFM.kinds("a|b\n-|-\n") == [.table])
        #expect(GFM.kinds("intro\na | b\n--|--\n1 | 2\n") == [.paragraph, .table])
        // The table ends where a row has no pipe.
        #expect(GFM.kinds("a | b\n---|---\n1 | 2\nplain\n") == [.table, .paragraph])
        #expect(GFM.kinds("a | b\n---|---\n1 | 2\n\ntext\n") == [.table, .paragraph])
        #expect(GFM.kinds("a | b\n---|---\n1 | 2\n# h\n") == [.table, .heading])
    }

    @Test("what is not a table stays text")
    func notTables() {
        #expect(GFM.kinds("a | b\n---\n") == [.setextHeading])               // no pipe in the delimiter row
        #expect(GFM.kinds("a | b | c\n---|---\n") == [.paragraph, .thematicBreak] || GFM.kinds("a | b | c\n---|---\n") == [.paragraph])
        #expect(!GFM.kinds("a | b | c\n---|---\n").contains(.table))          // cell counts differ
        #expect(!GFM.kinds("a | b\n--x|--\n").contains(.table))
        #expect(!GFM.kinds("just a | pipe\nnext line\n").contains(.table))
        #expect(!GFM.kinds("a \\| b\n---|---\n").contains(.table))             // escaped pipe is one cell
    }

    @Test("alignment colons and cells parse the same as the piped form")
    func alignment() throws {
        let loose = try #require(MarkdownStyler.parseTableSource("a | b | c\n:--|:-:|--:\n1 | 2 | 3\n"))
        let piped = try #require(MarkdownStyler.parseTableSource("| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |\n"))
        #expect(loose.header == piped.header && loose.rows == piped.rows)
        #expect(loose.alignments == [.left, .center, .right])
        #expect(loose.alignments == piped.alignments)
    }

    @Test("a table token covers the block, and renders as an image when the caret is away")
    func tokensAndRender() {
        let text = "a | b\n---|---\n1 | 2\n"
        let tokens = GFM.tokens(text).filter { $0.kind == .table }
        #expect(tokens.count == 1 && tokens[0].range == NSRange(location: 0, length: text.count - 1))
        let away = GFM.fullAttrs(text)
        #expect(away.contains { $0.attributes[.latexImage] != nil })
        #expect(!GFM.fullAttrs(text, caret: 2).contains { $0.attributes[.latexImage] != nil })
    }

    @Test("HTML export")
    func html() {
        #expect(MarkdownHTMLRenderer.html(from: "a | b\n---|---\n1 | <2>\n")
                == "<table><thead><tr><th>a</th><th>b</th></tr></thead><tbody><tr><td>1</td><td>&lt;2&gt;</td></tr></tbody></table>")
    }

    @Test("incremental parse equals full parse over table lines")
    func fuzz() {
        let templates = ["a | b", "---|---", "| a | b |", "|---|---|", "1 | 2", "plain", "", "# H", "- x | y", "> q | r", "```", "--|--"]
        let snippets = ["|", " | ", "-", "---", "\n", "\n\n", "x", "--|--"]
        for seed: UInt64 in (1...20).map({ UInt64($0) &* 0x7AB1 }) {
            GFM.fuzz(templates: templates, snippets: snippets, seed: seed)
        }
    }
}
