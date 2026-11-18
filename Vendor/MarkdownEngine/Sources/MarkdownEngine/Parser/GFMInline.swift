//
//  GFMInline.swift
//  MarkdownEngine
//
//  mlisb: inline recognition for reference-style links and images, footnote
//  references, and a safe subset of raw HTML (see `GFMHTML`). Matches surface
//  in the inline AST as extension-shaped nodes (`InlineNode.ext`) under the
//  reserved `gfm.` id namespace — like directives, so marker shrink, caret
//  reveal, token projection and rich copy apply unchanged.
//
//  Every scan here answers from a `BracketIndex` built in one linear pass per
//  parse: no candidate rescans forward from its own opener, so hostile text
//  (100k `[`, deep nesting, `[a][` repeated, endless `<b>`) stays linear.
//

import Foundation

/// One linear pass over a parse's text, answering the bracket, paren and
/// closing-tag questions the link-family scanners used to answer by rescanning
/// forward from every candidate. Tables are built lazily, on the first query.
final class BracketIndex {
    private let ns: NSString
    private let len: Int

    private struct Tables {
        var closeSameLine: [Int32]   // first `]` at/after i before any newline
        var nextBracket: [Int32]     // first `[` or `]` at/after i
        var pairBracket: [Int32]     // for a `[`: its balanced `]` (backslash escapes skipped)
        var pairParen: [Int32]       // for a `(`: its balanced `)` on the same line
    }
    private lazy var tables: Tables = build()
    private var closers: [String: [GFMHTML.Tag]]?

    init(_ ns: NSString, _ len: Int) {
        self.ns = ns
        self.len = len
    }

    private func build() -> Tables {
        var chars = [unichar](repeating: 0, count: len)
        if len > 0 { ns.getCharacters(&chars, range: NSRange(location: 0, length: len)) }
        var closeSameLine = [Int32](repeating: -1, count: len + 1)
        var nextBracket = [Int32](repeating: -1, count: len + 1)
        var pairBracket = [Int32](repeating: -1, count: len + 1)
        var pairParen = [Int32](repeating: -1, count: len + 1)
        var sameLine: Int32 = -1
        var bracket: Int32 = -1
        var i = len - 1
        while i >= 0 {
            let c = chars[i]
            if c == 0x5D { sameLine = Int32(i) } else if c == 0x0A { sameLine = -1 }
            if c == 0x5D || c == 0x5B { bracket = Int32(i) }
            closeSameLine[i] = sameLine
            nextBracket[i] = bracket
            i -= 1
        }
        var squares: [Int] = []
        var parens: [Int] = []
        var escaped = false
        for (k, c) in chars.enumerated() {
            if c == 0x0A { parens.removeAll(keepingCapacity: true) }
            if c == 0x28 { parens.append(k) } else if c == 0x29, let open = parens.popLast() { pairParen[open] = Int32(k) }
            if c == 0x5C { escaped.toggle(); continue }
            if !escaped {
                if c == 0x5B { squares.append(k) } else if c == 0x5D, let open = squares.popLast() { pairBracket[open] = Int32(k) }
            }
            escaped = false
        }
        return Tables(closeSameLine: closeSameLine, nextBracket: nextBracket, pairBracket: pairBracket, pairParen: pairParen)
    }

    private func lookup(_ array: [Int32], _ i: Int) -> Int? {
        guard i >= 0, i < len else { return nil }
        let v = array[i]
        return v < 0 ? nil : Int(v)
    }

    /// First `]` at or after `i` on the same line.
    func closeBracket(from i: Int) -> Int? { lookup(tables.closeSameLine, i) }
    /// First `[` or `]` at or after `i`.
    func nextBracket(from i: Int) -> Int? { lookup(tables.nextBracket, i) }
    /// The `]` balancing the `[` at `open`.
    func matchingBracket(of open: Int) -> Int? { lookup(tables.pairBracket, open) }
    /// The `)` balancing the `(` at `open`, on the same line.
    func matchingParen(of open: Int) -> Int? { lookup(tables.pairParen, open) }

    /// The first recognised `</name>` at or after `from`.
    func closingTag(named name: String, from: Int) -> GFMHTML.Tag? {
        if closers == nil {
            var found: [String: [GFMHTML.Tag]] = [:]
            var i = 0
            while i + 3 < len {
                if ns.character(at: i) == 0x3C, ns.character(at: i + 1) == 0x2F,
                   let t = GFMHTML.tag(ns, at: i, end: len), t.closing {
                    found[t.name, default: []].append(t)
                }
                i += 1
            }
            closers = found
        }
        guard let list = closers?[name] else { return nil }
        var lo = 0, hi = list.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if list[mid].range.location >= from { hi = mid } else { lo = mid + 1 }
        }
        return lo < list.count ? list[lo] : nil
    }
}

enum GFMInline {

    static let idPrefix = "gfm."
    static let refID = "gfm.ref"             // [text][label] · [label][] · [label]
    static let refImageID = "gfm.refimage"   // ![alt][label]
    static let footnoteID = "gfm.footnote"   // [^id]
    static let htmlPrefix = "gfm.html."      // gfm.html.kbd, gfm.html.br, gfm.html.img, …

    struct Match {
        let id: String
        let range: NSRange
        let contentRange: NSRange
        let markers: [NSRange]
        let parsesContent: Bool
        let target: String?
    }

    private static let lbracket: unichar = 0x5B
    private static let rbracket: unichar = 0x5D

    /// A construct opening at `i`, or nil (the characters stay literal).
    static func match(_ ns: NSString, _ len: Int, at i: Int, registry: ExtensionRegistry, index: BracketIndex) -> Match? {
        let c = ns.character(at: i)
        if c == lbracket, let refs = registry.references { return reference(ns, len, start: i, image: false, refs, index) }
        if c == 0x21, i + 1 < len, ns.character(at: i + 1) == lbracket, let refs = registry.references {
            return reference(ns, len, start: i, image: true, refs, index)
        }
        if c == 0x3C { return html(ns, len, start: i, index) }
        return nil
    }

    // MARK: - References and footnotes

    /// CommonMark: a link label holds at most 999 characters.
    private static let maxLabel = 999

    private static func reference(_ ns: NSString, _ len: Int, start i: Int, image: Bool,
                                  _ refs: ReferenceTable, _ index: BracketIndex) -> Match? {
        let open = image ? i + 1 : i
        let textStart = open + 1
        guard let closeText = index.matchingBracket(of: open), closeText > textStart else { return nil }
        let textRange = NSRange(location: textStart, length: closeText - textStart)

        if !image, ns.character(at: textStart) == 0x5E {   // [^id]
            // The id holds no brackets: the first bracket after `[^` is this `]`.
            guard textRange.length > 1, textRange.length <= maxLabel,
                  index.nextBracket(from: textStart + 1) == closeText else { return nil }
            let idRange = NSRange(location: textStart + 1, length: textRange.length - 1)
            let id = ns.substring(with: idRange)
            guard !id.contains(where: { $0.isWhitespace }),
                  refs.footnotes.contains(ReferenceTable.normalize(id)) else { return nil }
            return Match(id: footnoteID, range: NSRange(location: i, length: closeText + 1 - i),
                         contentRange: idRange,
                         markers: [NSRange(location: i, length: 2), NSRange(location: closeText, length: 1)],
                         parsesContent: false, target: nil)
        }

        var label: String?
        var end = closeText + 1
        if end < len, ns.character(at: end) == 0x28 { return nil }          // an inline link's `(`
        if end < len, ns.character(at: end) == lbracket {                    // [text][label] / [text][]
            // The label holds no brackets: it ends at the next bracket, which must be a `]`.
            guard let k = index.nextBracket(from: end + 1), ns.character(at: k) == rbracket,
                  k - end - 1 <= maxLabel else { return nil }
            if k > end + 1 { label = ns.substring(with: NSRange(location: end + 1, length: k - end - 1)) }
            end = k + 1
        }
        // The text doubles as the label for `[label]` and `[label][]`.
        if label == nil { guard textRange.length <= maxLabel else { return nil } }
        let key = ReferenceTable.normalize(label ?? ns.substring(with: textRange))
        guard let def = refs.links[key] else { return nil }
        return Match(id: image ? refImageID : refID, range: NSRange(location: i, length: end - i),
                     contentRange: textRange,
                     markers: [NSRange(location: i, length: image ? 2 : 1),
                               NSRange(location: closeText, length: end - closeText)],
                     parsesContent: !image, target: def.target)
    }

    // MARK: - HTML

    private static func html(_ ns: NSString, _ len: Int, start i: Int, _ index: BracketIndex) -> Match? {
        guard let open = GFMHTML.tag(ns, at: i, end: len), !open.closing else { return nil }
        let id = htmlPrefix + open.name
        switch open.name {
        case "br":
            return Match(id: id, range: open.range, contentRange: NSRange(location: NSMaxRange(open.range), length: 0),
                         markers: [open.range], parsesContent: false, target: nil)
        case "img":
            guard let src = open.attribute("src") else { return nil }
            // No markers: the tag is drawn as an image or shown muted, never shrunk piecemeal.
            return Match(id: id, range: open.range, contentRange: src.valueRange, markers: [], parsesContent: false, target: nil)
        case "a", "kbd", "sub", "sup", "b", "strong", "i", "em", "code", "s", "del", "u", "mark":
            guard let close = index.closingTag(named: open.name, from: NSMaxRange(open.range)) else { return nil }
            let content = NSRange(location: NSMaxRange(open.range), length: close.range.location - NSMaxRange(open.range))
            return Match(id: id, range: NSRange(location: i, length: NSMaxRange(close.range) - i), contentRange: content,
                         markers: [open.range, close.range], parsesContent: open.name != "code",
                         target: open.name == "a" ? open.attribute("href")?.value : nil)
        default:
            return nil   // block-level tags (details, p, h1…) are the block parser's
        }
    }
}
