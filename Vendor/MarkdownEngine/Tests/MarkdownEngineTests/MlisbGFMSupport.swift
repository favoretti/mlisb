//
//  MlisbGFMSupport.swift
//  MarkdownEngineTests
//
//  mlisb: helpers shared by the MlisbGFM*Tests suites.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

enum GFM {
    static let fontName = NSFont.systemFont(ofSize: 14).fontName

    static func kinds(_ text: String) -> [BlockKind] {
        BlockParser.computeBlocks(text).map(\.kind).filter { $0 != .blank }
    }

    static func tokens(_ text: String) -> [MarkdownToken] {
        MarkdownTokenizer.fullTokens(blocks: BlockParser.computeBlocks(text), ns: text as NSString)
    }

    static func attrs(_ text: String, caret: Int = -1, reveal: Bool = false,
                      configure: (inout MarkdownEditorConfiguration) -> Void = { _ in }) -> [StyledRange] {
        _ = NSApplication.shared
        var config = MarkdownEditorConfiguration.default
        config.revealAllSyntax = reveal
        configure(&config)
        return MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: 14, caretLocation: caret, configuration: config)
    }

    /// The last value any styled range sets for `key` at `index` (later ranges win).
    static func value(_ key: NSAttributedString.Key, at index: Int, in attrs: [StyledRange]) -> Any? {
        attrs.last { NSLocationInRange(index, $0.range) && $0.attributes[key] != nil }?.attributes[key]
    }

    static func fontSize(at index: Int, in attrs: [StyledRange]) -> CGFloat {
        (value(.font, at: index, in: attrs) as? NSFont)?.pointSize ?? 14
    }

    static func isHidden(_ index: Int, in attrs: [StyledRange]) -> Bool {
        fontSize(at: index, in: attrs) < 2 || (value(.foregroundColor, at: index, in: attrs) as? NSColor) == .clear
    }

    static func bold(at index: Int, in attrs: [StyledRange]) -> Bool {
        (value(.font, at: index, in: attrs) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
    }

    static func italic(at index: Int, in attrs: [StyledRange]) -> Bool {
        (value(.font, at: index, in: attrs) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) == true
    }

    /// Full styled pipeline (AST + image passes), caret outside every construct unless given.
    static func fullAttrs(_ text: String, caret: Int = -1, services: MarkdownEditorServices = .default) -> [StyledRange] {
        _ = NSApplication.shared
        var config = MarkdownEditorConfiguration.default
        config.services = services
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: text)
        let active = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: NSRange(location: max(caret, 0), length: 0), tokens: tokens, in: text as NSString,
            suppressed: caret < 0)
        return MarkdownStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: 14, caretLocation: caret,
            activeTokenIndices: active, configuration: config)
    }

    // MARK: Incremental ≡ full

    struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func int(_ upper: Int) -> Int { upper <= 0 ? 0 : Int(next() % UInt64(upper)) }
        mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
    }

    static func dump(_ tokens: [MarkdownToken]) -> [String] {
        tokens.map { "\($0.kind)|\($0.range)|\($0.contentRange)|\($0.markerRanges)" }
    }

    /// Random edits over `templates`; after each, descriptor-driven and scan-driven incremental parses
    /// must equal a from-scratch parse (blocks and tokens).
    static func fuzz(templates: [String], snippets: [String], seed: UInt64, steps: Int = 300) {
        for useDescriptor in [true, false] {
            var rng = Rng(state: seed)
            let state = DocumentParseState()
            var text = (0..<30).map { _ in rng.pick(templates) }.joined(separator: "\n")
            _ = state.tokens(for: text, edit: nil)
            for step in 0..<steps {
                let ns = NSMutableString(string: text)
                let loc = rng.int(ns.length + 1)
                let removeLen = min(rng.int(6), ns.length - loc)
                let insert = rng.int(4) == 0 ? "" : rng.pick(snippets)
                ns.replaceCharacters(in: NSRange(location: loc, length: removeLen), with: insert)
                text = ns as String
                let edit = useDescriptor
                    ? ParseEditDescriptor(editedRange: NSRange(location: loc, length: (insert as NSString).length),
                                          delta: (insert as NSString).length - removeLen)
                    : nil
                let incremental = dump(state.tokens(for: text, edit: edit))
                let fullBlocks = BlockParser.computeBlocks(text)
                let full = dump(MarkdownTokenizer.fullTokens(blocks: fullBlocks, ns: text as NSString))
                let blocksOK = state.currentBlocks == fullBlocks
                #expect(incremental == full && blocksOK,
                        "seed \(seed) step \(step) descriptor=\(useDescriptor): diverged after editing at \(loc) (-\(removeLen) +\(insert.debugDescription))")
                if incremental != full || !blocksOK {
                    print("FUZZ text=\(text.debugDescription)")
                    print("FUZZ incr=\(state.currentBlocks.map { "\($0.kind)\($0.range)" })")
                    print("FUZZ full=\(fullBlocks.map { "\($0.kind)\($0.range)" })")
                    return
                }
            }
        }
    }
}
