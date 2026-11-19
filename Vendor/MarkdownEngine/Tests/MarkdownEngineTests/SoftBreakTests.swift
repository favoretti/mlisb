//
//  SoftBreakTests.swift
//  MarkdownEngineTests
//
//  mlisb: paragraph lines shown joined, hidden link targets that do not wrap, and code blocks
//  that use the room beside the text column.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@Suite("mlisb joined paragraph lines")
struct SoftBreakTextTests {
    private let sp = "\u{2005}"

    @Test("A paragraph's lines are joined, at the same length")
    func joinsParagraphLines() {
        let text = "The Go port of the tool,\nproven record for record.\nThe end.\n"
        let shown = SoftBreaks.display(text)
        #expect(shown == "The Go port of the tool,\(sp)proven record for record.\(sp)The end.\n")
        #expect(shown.utf16.count == text.utf16.count)
        #expect(SoftBreaks.storage(shown) == text)
    }

    @Test("Hard breaks, separate paragraphs and other blocks keep their lines")
    func keepsRealBreaks() {
        for text in [
            "two spaces  \nnext\n",
            "backslash\\\nnext\n",
            "one\n\ntwo\n",
            "# Heading\ntext\n",
            "Title\n=====\n",
            "- one\n- two\n",
            "```\ncode\nmore\n```\n",
            "| a | b |\n|---|---|\n| 1 | 2 |\n",
            "> # quoted heading\n> text\n",
            "> one\n>\n> two\n",
            "> outer\n> > inner\n",
        ] {
            #expect(SoftBreaks.display(text) == text, "\(text.debugDescription)")
        }
    }

    @Test("The next line's indentation and quote markers are hidden with the break")
    func hidesContinuationPrefixes() {
        #expect(SoftBreaks.display("- an item\n  that goes on\n") == "- an item\(sp)\u{FE00}\u{FE00}that goes on\n")
        #expect(SoftBreaks.display("> quoted\n> text\n") == "> quoted\(sp)\u{FE02}\u{FE00}text\n")
        #expect(SoftBreaks.display("> quoted\nlazy\n") == "> quoted\(sp)lazy\n")
        #expect(SoftBreaks.display("para\n\tindented\n") == "para\(sp)\u{FE01}indented\n")
    }

    @Test("Windows line endings come back intact")
    func crlf() {
        let text = "one\r\ntwo\r\n\r\nthree\r\n"
        let shown = SoftBreaks.display(text)
        #expect(shown == "one\u{FE03}\(sp)two\r\n\r\nthree\r\n")
        #expect(SoftBreaks.storage(shown) == text)
    }

    @Test("Text that already holds a stand-in is shown as it is")
    func leavesStandInsAlone() {
        let text = "a\(sp)b\nc\n"
        #expect(!SoftBreaks.applies(to: text))
        #expect(SoftBreaks.display(text) == text)
    }

    @Test("Every document comes back byte for byte")
    func roundTrips() {
        let corpus = [
            "# Title\n\nSome text that\nwraps by hand\nacross lines.\n\n- a list item\n  continued\n- next\n\n> a quote\n> on two lines\n\n```swift\nlet x = 1\nlet y = 2\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n",
            "no newline at the end\nsecond line",
            "  indented\n    more indented\n",
            "a  \nb\\\nc\nd\n",
            "* [ ] task\n  more\n",
            "1. one\n   two\n",
            "",
            "\n\n\n",
        ]
        for text in corpus {
            let shown = SoftBreaks.display(text)
            #expect(shown.utf16.count == text.utf16.count)
            #expect(SoftBreaks.storage(shown) == text, "\(text.debugDescription)")
        }
    }
}

@MainActor
@Suite("mlisb joined lines in the editor", .serialized)
struct SoftBreakEditorTests {
    final class Model: ObservableObject {
        @Published var text: String
        @Published var reveal = false
        var inset: CGFloat = 0
        var room: CGFloat = 0
        init(_ text: String) { self.text = text }
    }

    private struct Host: View {
        @ObservedObject var model: Model
        var body: some View {
            var config = MarkdownEditorConfiguration.default
            config.revealAllSyntax = model.reveal
            config.textInsets = TextInsets(horizontal: model.inset, vertical: 0)
            config.wideTableOverflow = model.room
            return NativeTextViewWrapper(text: $model.text, configuration: config)
        }
    }

    private static var windows: [NSWindow] = []

    private static func findScrollView(_ root: NSView) -> NSScrollView? {
        if let sv = root as? NSScrollView, sv.nativeTextView != nil { return sv }
        for sub in root.subviews { if let f = findScrollView(sub) { return f } }
        return nil
    }

    private static func spin(_ seconds: TimeInterval) async {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    static func stage(_ model: Model, width: CGFloat = 900) async throws -> (NativeTextView, NativeTextViewCoordinator) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: width, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(model: model))
        window.orderFrontRegardless()
        windows.append(window)
        await spin(0.4)
        let sv = try #require(findScrollView(window.contentView!))
        let tv = try #require(sv.nativeTextView)
        return (tv, try #require(tv.delegate as? NativeTextViewCoordinator))
    }

    @Test("Typing in a joined paragraph saves the file's own line breaks, through undo too")
    func typingKeepsLineBreaks() async throws {
        let model = Model("first line\nsecond line\n")
        let (tv, _) = try await Self.stage(model)
        #expect(tv.string == "first line\u{2005}second line\n")
        tv.insertText("!", replacementRange: NSRange(location: 5, length: 0))
        await Self.spin(0.2)
        #expect(model.text == "first! line\nsecond line\n")
        // Deleting the joined break joins the file's lines; undoing it brings the break back.
        tv.insertText("", replacementRange: NSRange(location: 11, length: 1))
        await Self.spin(0.2)
        #expect(model.text == "first! linesecond line\n")
        tv.undoManager?.undo()
        await Self.spin(0.2)
        #expect(tv.string == "first! line\u{2005}second line\n")
        tv.insertText("?", replacementRange: NSRange(location: 0, length: 0))
        await Self.spin(0.2)
        #expect(model.text == "?first! line\nsecond line\n")
    }

    @Test("Copy carries the file's line breaks")
    func copyKeepsLineBreaks() async throws {
        let model = Model("first line\nsecond line\n")
        let (tv, _) = try await Self.stage(model)
        tv.setSelectedRange(NSRange(location: 0, length: 22))
        tv.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == "first line\nsecond line")
    }

    @Test("Source mode shows the file's line breaks, and leaving it joins them again")
    func sourceMode() async throws {
        let model = Model("first line\nsecond line\n")
        let (tv, _) = try await Self.stage(model)
        model.reveal = true
        await Self.spin(0.3)
        #expect(tv.string == "first line\nsecond line\n")
        model.reveal = false
        await Self.spin(0.3)
        #expect(tv.string == "first line\u{2005}second line\n")
        #expect(model.text == "first line\nsecond line\n")
    }

    @Test("A hidden link target leaves the line nowhere to wrap")
    func linkTargetDoesNotWrap() async throws {
        let model = Model("see [Parity](#parity-with-the-java). Design\n")
        let (tv, c) = try await Self.stage(model)
        let storage = try #require(tv.textContentStorage)
        let ns = tv.string as NSString
        let paragraph = try #require(c.textContentStorage(storage, textParagraphWith: NSRange(location: 0, length: ns.length)))
        let laidOut = paragraph.attributedString.string
        #expect(laidOut.utf16.count == ns.length)
        #expect(!laidOut.contains("(#parity"))
        #expect(laidOut.contains("]\u{2060}"))
    }

    @Test("Code blocks use the room beside the column; paragraphs keep its width")
    func codeBlocksUseTheRoom() async throws {
        let prose = String(repeating: "word ", count: 120)
        let code = String(repeating: "x", count: 400)
        let model = Model("\(prose)\n\n```\n\(code)\n```\n")
        model.inset = 300
        model.room = 250
        let (tv, _) = try await Self.stage(model, width: 1200)
        await Self.spin(0.3)
        let tlm = try #require(tv.textLayoutManager)
        tlm.ensureLayout(for: tlm.documentRange)
        let ns = tv.string as NSString
        let codeStart = ns.range(of: "xxx").location
        var proseRight: CGFloat = 0
        var codeRight: CGFloat = 0
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = tlm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments {
                let right = fragment.layoutFragmentFrame.minX + line.typographicBounds.maxX
                if start < codeStart - 10 { proseRight = max(proseRight, right) } else if start >= codeStart - 4 { codeRight = max(codeRight, right) }
            }
            return true
        }
        #expect(proseRight <= 601, "prose \(proseRight) code \(codeRight) frame \(tv.frame) pinned \(String(describing: tv.pinnedTextWidth)) container \(tv.textContainer!.size)")
        #expect(proseRight > 500, "prose \(proseRight) code \(codeRight) frame \(tv.frame) pinned \(String(describing: tv.pinnedTextWidth)) container \(tv.textContainer!.size)")
        #expect(codeRight > 700)
        #expect(codeRight <= 851)
    }
}

