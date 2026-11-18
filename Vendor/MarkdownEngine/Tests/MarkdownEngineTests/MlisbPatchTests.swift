//
//  MlisbPatchTests.swift
//  MarkdownEngineTests
//
//  mlisb: tests for the local patches listed in PATCHES.md.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

// MARK: - Styler-level patches

@MainActor
@Suite("mlisb styler patches")
struct MlisbStylerTests {

    private let fontName = NSFont.systemFont(ofSize: 14).fontName

    private func attrs(_ text: String, caret: Int = -1, reveal: Bool = false) -> [StyledRange] {
        _ = NSApplication.shared
        var config = MarkdownEditorConfiguration.default
        config.revealAllSyntax = reveal
        return MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: 14, caretLocation: caret, configuration: config)
    }

    private func paragraphStyle(at index: Int, in attrs: [StyledRange]) -> NSParagraphStyle? {
        attrs.last { NSLocationInRange(index, $0.range) && $0.attributes[.paragraphStyle] != nil }?
            .attributes[.paragraphStyle] as? NSParagraphStyle
    }

    private func isHidden(_ index: Int, in attrs: [StyledRange]) -> Bool {
        let size = attrs.last { NSLocationInRange(index, $0.range) && $0.attributes[.font] != nil }
            .flatMap { ($0.attributes[.font] as? NSFont)?.pointSize }
        return (size ?? 14) < 2
    }

    @Test("revealAllSyntax shows markers that are hidden away from the caret")
    func revealShowsSyntax() {
        let text = "a **bold** b\n"
        #expect(isHidden(2, in: attrs(text)))
        #expect(!isHidden(2, in: attrs(text, reveal: true)))
        // Text keeps its styling.
        let bold = attrs(text, reveal: true).last { NSLocationInRange(4, $0.range) && $0.attributes[.font] != nil }
        #expect((bold?.attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("revealAllSyntax keeps the bullet and ordered numbers as authored")
    func revealListMarkers() {
        #expect(attrs("- a\n").contains { $0.attributes[.bulletMarker] != nil })
        #expect(!attrs("- a\n", reveal: true).contains { $0.attributes[.bulletMarker] != nil })
        #expect(attrs("1. a\n1. b\n").contains { $0.attributes[.orderedMarker] != nil })
        #expect(!attrs("1. a\n1. b\n", reveal: true).contains { $0.attributes[.orderedMarker] != nil })
    }

    @Test("revealAllSyntax reveals every token")
    func revealAllTokens() {
        let text = "# h\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n$$x$$\n"
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: text)
        #expect(MarkdownDetection.computeActiveTokenIndices(
            selectionRange: NSRange(location: 0, length: 0), tokens: tokens, in: text as NSString,
            suppressed: true, revealAll: true) == Set(tokens.indices))
        #expect(MarkdownDetection.computeActiveTokenIndices(
            selectionRange: NSRange(location: 0, length: 0), tokens: tokens, in: text as NSString,
            suppressed: true) == [])
    }

    @Test("continuation line aligns with the item text at every level and item kind")
    func continuationAligns() {
        let cases = ["- first\n  second\n", "1. first\n   second\n", "- [ ] first\n  second\n",
                     "- top\n  - nested\n    second\n", "- top\n\t- nested\n\t  second\n"]
        for text in cases {
            let ns = text as NSString
            let first = ns.range(of: "first").location != NSNotFound ? "first" : "nested"
            let second = ns.range(of: "second").location
            let itemLine = ns.range(of: first).location
            let a = attrs(text)
            let item = paragraphStyle(at: itemLine, in: a)
            let cont = paragraphStyle(at: second, in: a)
            #expect(item != nil && cont != nil, "\(text.debugDescription)")
            #expect(cont?.firstLineHeadIndent == item?.headIndent, "\(text.debugDescription)")
            #expect(cont?.headIndent == item?.headIndent, "\(text.debugDescription)")
            // The source indentation of the continuation adds no width.
            #expect(isHidden(ns.range(of: "second").location - 1, in: a), "\(text.debugDescription)")
        }
    }

    @Test("a blank line or a new marker ends the item")
    func continuationEnds() {
        let blank = attrs("- first\n\nplain\n")
        #expect(paragraphStyle(at: 9, in: blank) == nil)
        let marker = attrs("- first\n- second\n")
        #expect(paragraphStyle(at: 10, in: marker)?.firstLineHeadIndent
                == paragraphStyle(at: 2, in: marker)?.firstLineHeadIndent)
    }

    @Test("a scoped restyle of only the continuation line still aligns it")
    func continuationScoped() {
        _ = NSApplication.shared
        let text = "- first\n  second\n"
        let scoped = MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: 14,
            scopedRanges: [NSRange(location: 8, length: 9)], configuration: .default)
        let full = attrs(text)
        #expect(paragraphStyle(at: 10, in: scoped)?.headIndent == paragraphStyle(at: 10, in: full)?.headIndent)
        #expect((paragraphStyle(at: 10, in: scoped)?.headIndent ?? 0) > 0)
    }

    @Test("continuation does not change the text")
    func continuationTextUntouched() {
        let tv = NativeTextView(frame: .zero)
        let c = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil)
        c.rebuildTextStorageAndStyle(tv, from: "- first\n  second\n")
        #expect(tv.string == "- first\n  second\n")
    }
}

// MARK: - Arrow replacement

@MainActor
@Suite("mlisb arrow replacement")
struct MlisbArrowTests {

    private func type(_ s: String, arrow: Bool?) -> String {
        _ = NSApplication.shared
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        tv.isEditable = true
        var config = MarkdownEditorConfiguration.default
        if let arrow { config.lists.arrowReplacementEnabled = arrow }
        tv.configuration = config
        tv.string = "a -"
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        _ = MarkdownLists.handleInsertion(textView: tv, affectedCharRange: NSRange(location: 3, length: 0),
                                          replacementString: s, isInsideCodeBlock: false)
        return tv.string
    }

    @Test func defaultRewritesArrow() {
        #expect(type(">", arrow: nil) == "a →")
        #expect(MarkdownEditorConfiguration.default.lists.arrowReplacementEnabled)
    }

    @Test func optOutLeavesTextAlone() {
        // The handler declines to rewrite, so the keystroke proceeds as typed.
        #expect(type(">", arrow: false) == "a -")
    }
}

// MARK: - Hosted: links, reveal flip, external replace

@MainActor
@Suite("mlisb hosted editor", .serialized)
struct MlisbHostedTests {

    private final class Model: ObservableObject {
        @Published var text: String
        @Published var reveal = false
        var opened: [String] = []
        var handle = true
        var useHook = true
        init(_ text: String) { self.text = text }
    }

    private struct Host: View {
        @ObservedObject var model: Model
        var body: some View {
            var config = MarkdownEditorConfiguration.default
            config.revealAllSyntax = model.reveal
            var view = NativeTextViewWrapper(text: $model.text, configuration: config)
            if model.useHook {
                view.onOpenLink = { target in model.opened.append(target); return model.handle }
            }
            return view
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

    private static func stage(_ model: Model) async throws -> (NSScrollView, NativeTextView, NativeTextViewCoordinator) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 900, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(model: model))
        window.orderFrontRegardless()
        windows.append(window)
        await spin(0.4)
        let sv = try #require(findScrollView(window.contentView!))
        let tv = try #require(sv.nativeTextView)
        return (sv, tv, try #require(tv.delegate as? NativeTextViewCoordinator))
    }

    private func click(_ tv: NativeTextView, _ c: NativeTextViewCoordinator, on needle: String) throws -> Bool {
        let ns = tv.string as NSString
        let loc = ns.range(of: needle).location + needle.count / 2
        let link = try #require(tv.textStorage?.attribute(.link, at: loc, effectiveRange: nil))
        return c.textView(tv, clickedOnLink: link, at: loc)
    }

    @Test("onOpenLink gets the raw target as written")
    func rawTargets() async throws {
        let model = Model("[a](./other.md) [b](#anchor) [c](mailto:a@b.co) [d](https://x.org/p) www.example.com/q\n")
        let (_, tv, c) = try await Self.stage(model)
        let ns = tv.string as NSString
        for label in ["a", "b", "c", "d"] {
            // Labels are one char: click the char itself (a 1-2 char link has no edit zone).
            let loc = ns.range(of: "[\(label)](").location + 1
            let link = try #require(tv.textStorage?.attribute(.link, at: loc, effectiveRange: nil))
            #expect(c.textView(tv, clickedOnLink: link, at: loc))
        }
        #expect(model.opened == ["./other.md", "#anchor", "mailto:a@b.co", "https://x.org/p"])
    }

    @Test("bare URL passes its text; false falls through; nil hook is today's behaviour")
    func bareAndFallthrough() async throws {
        let model = Model("see https://example.com/page now\n")
        let (_, tv, c) = try await Self.stage(model)
        #expect(try click(tv, c, on: "https://example.com/page"))
        #expect(model.opened == ["https://example.com/page"])

        model.handle = false
        model.text += " "   // force an update pass
        await Self.spin(0.2)
        #expect(try click(tv, c, on: "https://example.com/page") == false)

        model.useHook = false
        model.text += " "
        await Self.spin(0.2)
        let count = model.opened.count
        #expect(try click(tv, c, on: "https://example.com/page") == false)
        #expect(model.opened.count == count)
    }

    @Test("with no hook, only web and mail addresses fall through to AppKit")
    func unhandledSchemesAreNotOpened() async throws {
        let model = Model("[f](file:///Applications/Calculator.app) [s](ssh://host/x) [r][k] [w](https://x.org/p)\n\n[k]: vnc://host\n")
        model.useHook = false
        let (_, tv, c) = try await Self.stage(model)
        let ns = tv.string as NSString
        for (label, falls) in [("f", false), ("s", false), ("r", false), ("w", true)] {
            let loc = ns.range(of: "[\(label)]").location + 1
            let link = try #require(tv.textStorage?.attribute(.link, at: loc, effectiveRange: nil))
            #expect(c.textView(tv, clickedOnLink: link, at: loc) == !falls, "\(label)")
        }
    }

    @Test("flipping revealAllSyntax restyles in place and keeps undo")
    func revealFlip() async throws {
        let model = Model("a **bold** b\n")
        let (_, tv, c) = try await Self.stage(model)
        let manager = c.undoManagers[c.documentId ?? ""]
        func markerSize() -> CGFloat {
            (tv.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        }
        #expect(markerSize() < 2)
        let storage = tv.textStorage
        model.reveal = true
        await Self.spin(0.3)
        #expect(markerSize() > 5)
        #expect(tv.textStorage === storage)
        #expect(c.undoManagers[c.documentId ?? ""] === manager)
        model.reveal = false
        await Self.spin(0.3)
        #expect(markerSize() < 2)
    }

    @Test("external text replace keeps the caret and the scroll position")
    func externalReplaceKeepsCaretAndScroll() async throws {
        let lines = (0..<200).map { "line \($0)" }.joined(separator: "\n\n")
        let model = Model(lines)
        let (sv, tv, _) = try await Self.stage(model)
        tv.setSelectedRange(NSRange(location: 40, length: 3))
        sv.contentView.scroll(to: NSPoint(x: 0, y: 900))
        sv.reflectScrolledClipView(sv.contentView)
        await Self.spin(0.2)
        let y = sv.contentView.bounds.origin.y
        #expect(y > 500)

        model.text = lines.replacingOccurrences(of: "line 3\n", with: "LINE 3\n")
        await Self.spin(0.4)
        #expect(tv.string.contains("LINE 3"))
        #expect(tv.selectedRange() == NSRange(location: 40, length: 3))
        #expect(abs(sv.contentView.bounds.origin.y - y) < 1)

        // Shorter text clamps the selection to the new length.
        model.text = "short"
        await Self.spin(0.4)
        #expect(tv.selectedRange() == NSRange(location: 5, length: 0))
    }
}
