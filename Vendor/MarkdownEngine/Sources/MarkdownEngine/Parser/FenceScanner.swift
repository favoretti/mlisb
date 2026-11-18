//
//  FenceScanner.swift
//  MarkdownEngine
//
//  mlisb: fenced code block recognition per CommonMark — backtick or tilde
//  fences of 3+ characters, up to 3 spaces of indent, optionally after `>`
//  quote markers or (indent 4+) inside a list item. Pure line scanners over
//  absolute UTF-16 line ranges; the block parser decides list context.
//

import Foundation

/// An opening fence line, geometry relative to the line start.
struct FenceOpening: Equatable {
    let quoteDepth: Int      // `>` markers before the fence run
    let indent: Int          // columns between the container prefix and the fence run
    let char: unichar        // 0x60 or 0x7E
    let length: Int          // run length, >= 3
    let fenceStart: Int      // offset of the fence run within the line
    let info: NSRange        // info string (language), absolute-relative to line start, untrimmed
}

enum FenceScanner {

    enum LineRole { case content, closer, exit }

    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09
    private static let gt: unichar = 0x3E
    private static let backtick: unichar = 0x60
    private static let tilde: unichar = 0x7E

    /// End of a line's content (excluding the line break).
    private static func contentEnd(_ ns: NSString, _ line: NSRange) -> Int {
        var e = NSMaxRange(line)
        while e > line.location, ns.character(at: e - 1) == 0x0A || ns.character(at: e - 1) == 0x0D { e -= 1 }
        return e
    }

    /// Skips `>` markers (each with one optional space), after up to 3 leading
    /// spaces. Returns the index after the prefix and the marker count; stops
    /// early at `limit` markers.
    private static func skipQuotes(_ ns: NSString, _ from: Int, _ end: Int, limit: Int = Int.max) -> (index: Int, depth: Int) {
        var i = from
        var lead = 0
        while i < end, lead < 3, ns.character(at: i) == space { i += 1; lead += 1 }
        var depth = 0
        guard i < end, ns.character(at: i) == gt else { return (from, 0) }
        while depth < limit, i < end, ns.character(at: i) == gt {
            depth += 1; i += 1
            if i < end, ns.character(at: i) == space || ns.character(at: i) == tab { i += 1 }
            // `> > ` — nested markers may be separated by spaces.
        }
        return (i, depth)
    }

    /// Opening fence on `line`, or nil. Indent 4+ is reported, not rejected —
    /// the caller accepts it only inside a list item.
    static func opening(in ns: NSString, line: NSRange) -> FenceOpening? {
        let end = contentEnd(ns, line)
        let (afterQuotes, depth) = skipQuotes(ns, line.location, end)
        var i = afterQuotes
        var indent = 0
        while i < end, ns.character(at: i) == space || ns.character(at: i) == tab {
            indent += ns.character(at: i) == tab ? 4 : 1
            i += 1
        }
        if depth > 0, indent > 3 { return nil }
        guard i < end else { return nil }
        let ch = ns.character(at: i)
        guard ch == backtick || ch == tilde else { return nil }
        var j = i
        while j < end, ns.character(at: j) == ch { j += 1 }
        let run = j - i
        guard run >= 3 else { return nil }
        let info = NSRange(location: j - line.location, length: end - j)
        if ch == backtick {   // a backtick fence's info string cannot hold backticks
            for k in j..<end where ns.character(at: k) == backtick { return nil }
        }
        return FenceOpening(quoteDepth: depth, indent: indent, char: ch, length: run,
                            fenceStart: i - line.location, info: info)
    }

    /// Role of a line after `open`: closer, ordinary content, or outside the
    /// container (a quoted fence ends where the `>` prefix stops).
    static func role(of line: NSRange, in ns: NSString, after open: FenceOpening) -> LineRole {
        let end = contentEnd(ns, line)
        var i = line.location
        if open.quoteDepth > 0 {
            let (idx, depth) = skipQuotes(ns, i, end, limit: open.quoteDepth)
            guard depth == open.quoteDepth else { return .exit }
            i = idx
        }
        var indent = 0
        while i < end, ns.character(at: i) == space || ns.character(at: i) == tab {
            indent += ns.character(at: i) == tab ? 4 : 1
            i += 1
        }
        guard indent <= (open.indent >= 4 ? open.indent + 3 : 3), i < end,
              ns.character(at: i) == open.char else { return .content }
        var j = i
        while j < end, ns.character(at: j) == open.char { j += 1 }
        guard j - i >= open.length else { return .content }
        for k in j..<end where ns.character(at: k) != space && ns.character(at: k) != tab { return .content }
        return .closer
    }

    /// Characters of container prefix and fence indentation to strip from a
    /// content line, so the code reads as the spec says.
    static func prefixLength(of line: NSRange, in ns: NSString, for open: FenceOpening) -> Int {
        let end = contentEnd(ns, line)
        var i = line.location
        if open.quoteDepth > 0 { i = skipQuotes(ns, i, end, limit: open.quoteDepth).index }
        var remaining = open.indent
        while remaining > 0, i < end, ns.character(at: i) == space { i += 1; remaining -= 1 }
        return i - line.location
    }

    /// The trimmed info string of an opening fence line, nil when empty.
    static func language(ofOpenerLine line: NSRange, in ns: NSString) -> String? {
        guard let open = opening(in: ns, line: line) else { return nil }
        let raw = ns.substring(with: NSRange(location: line.location + open.info.location, length: open.info.length))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    /// Opening fence of a fenced block whose range starts at `range.location`.
    static func opening(ofBlock range: NSRange, in ns: NSString) -> FenceOpening? {
        opening(in: ns, line: ns.lineRange(for: NSRange(location: range.location, length: 0)))
    }

    /// The block's code lines with prefixes stripped, plus a map from each
    /// stripped line back to its absolute source start. `closer` is the
    /// closing fence line when the block has one.
    static func body(ofBlock range: NSRange, in ns: NSString, open: FenceOpening)
        -> (lines: [(source: NSRange, prefix: Int)], opener: NSRange, closer: NSRange?) {
        let end = NSMaxRange(range)
        let opener = NSIntersectionRange(ns.lineRange(for: NSRange(location: range.location, length: 0)), range)
        var lines: [(NSRange, Int)] = []
        var closer: NSRange?
        var cursor = NSMaxRange(opener)
        while cursor < end {
            let line = NSIntersectionRange(ns.lineRange(for: NSRange(location: cursor, length: 0)), range)
            guard line.length > 0 else { break }
            cursor = NSMaxRange(line)
            if cursor >= end, role(of: line, in: ns, after: open) == .closer {
                closer = line
            } else {
                lines.append((line, prefixLength(of: line, in: ns, for: open)))
            }
        }
        return (lines, opener, closer)
    }

    /// Code text with the container prefixes stripped, and the offset in `ns`
    /// of each stripped line (for mapping highlight ranges back).
    static func strippedCode(lines: [(source: NSRange, prefix: Int)], in ns: NSString)
        -> (text: String, segments: [(stripped: Int, source: Int, length: Int)]) {
        var text = ""
        var segments: [(Int, Int, Int)] = []
        var offset = 0
        for (source, prefix) in lines {
            let piece = NSRange(location: source.location + prefix, length: max(0, source.length - prefix))
            text += ns.substring(with: piece)
            segments.append((offset, piece.location, piece.length))
            offset += piece.length
        }
        return (text, segments)
    }
}
