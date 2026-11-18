//
//  MlisbGFMAlertTests.swift
//  MarkdownEngineTests
//
//  mlisb: `> [!NOTE]` style alerts.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("mlisb GFM alerts")
struct MlisbGFMAlertTests {

    private let colors: [(String, String, NSColor)] = [
        ("NOTE", "Note", .systemBlue), ("TIP", "Tip", .systemGreen), ("IMPORTANT", "Important", .systemPurple),
        ("WARNING", "Warning", .systemOrange), ("CAUTION", "Caution", .systemRed),
    ]

    @Test("each alert kind colours the bar of every line and swaps the marker for its title")
    func styling() {
        for (marker, title, color) in colors {
            let text = "> [!\(marker)]\n> body line\n> more\n\nafter\n"
            let ns = text as NSString
            let m = ns.range(of: "[!").location
            let body = ns.range(of: "body").location
            let a = GFM.attrs(text)
            #expect((GFM.value(.blockquoteBarColor, at: body, in: a) as? NSColor) == color, "\(marker)")
            #expect((GFM.value(.blockquoteBarColor, at: m, in: a) as? NSColor) == color, "\(marker)")
            #expect(GFM.value(.blockquoteBarColor, at: ns.range(of: "after").location, in: a) == nil, "\(marker)")
            #expect(GFM.value(.alertTitle, at: m, in: a) as? String == title, "\(marker)")
            #expect((GFM.value(.foregroundColor, at: m, in: a) as? NSColor) == .clear, "\(marker)")
        }
    }

    @Test("the marker text shows with the caret on its line and in source mode")
    func markerReveal() {
        let text = "> [!NOTE]\n> body\n"
        let m = (text as NSString).range(of: "[!").location
        let onLine = GFM.attrs(text, caret: m + 2)
        #expect(GFM.value(.alertTitle, at: m, in: onLine) == nil)
        #expect((GFM.value(.foregroundColor, at: m, in: onLine) as? NSColor) == .systemBlue)
        #expect(GFM.value(.blockquoteBarColor, at: m, in: onLine) != nil)
        // Caret on the body line: the title still replaces the marker.
        #expect(GFM.value(.alertTitle, at: m, in: GFM.attrs(text, caret: text.count - 2)) != nil)
        #expect(GFM.value(.alertTitle, at: m, in: GFM.attrs(text, reveal: true)) == nil)
    }

    @Test("only a lone marker on the first line of a plain quote opens an alert")
    func notAlerts() {
        for text in ["> [!NOTE] inline text\n", "> [!INFO]\n> x\n", "> text\n> [!NOTE]\n", "> > [!NOTE]\n",
                     "> [!NOTE\n", "[!NOTE]\n"] {
            let m = (text as NSString).range(of: "[!").location
            #expect(GFM.value(.alertTitle, at: m, in: GFM.attrs(text)) == nil, "\(text.debugDescription)")
            #expect(!GFM.attrs(text).contains { $0.attributes[.blockquoteBarColor] != nil }, "\(text.debugDescription)")
        }
        #expect(GFM.value(.alertTitle, at: 2, in: GFM.attrs("> [!note]\n> x\n")) as? String == "Note")
    }

    @Test("HTML export is a GitHub alert block with escaped body")
    func html() {
        #expect(MarkdownHTMLRenderer.html(from: "> [!WARNING]\n> a < b\n")
                == "<div class=\"markdown-alert markdown-alert-warning\"><p class=\"markdown-alert-title\">Warning</p><p>a &lt; b</p></div>")
        #expect(MarkdownHTMLRenderer.html(from: "> [!TIP]\n")
                == "<div class=\"markdown-alert markdown-alert-tip\"><p class=\"markdown-alert-title\">Tip</p></div>")
        #expect(MarkdownHTMLRenderer.html(from: "> plain\n") == "<blockquote>plain</blockquote>")
    }
}
