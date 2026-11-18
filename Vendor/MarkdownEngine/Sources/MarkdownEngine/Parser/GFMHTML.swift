//
//  GFMHTML.swift
//  MarkdownEngine
//
//  mlisb: a safe subset of raw HTML. Only the tags and attributes listed here
//  are ever recognised; anything else — event handlers, `style`, `<script>`,
//  `<iframe>`, `<object>`, unknown tags or attributes, `javascript:` targets —
//  fails to match and stays literal text. Nothing is fetched or executed: an
//  `<img>` only names a source for the embedder's image provider, and an `<a>`
//  click goes through `onOpenLink` like any other link.
//

import Foundation

enum GFMHTML {

    struct Attribute {
        let name: String      // lowercased
        let value: String
        let valueRange: NSRange
    }

    struct Tag {
        let name: String      // lowercased
        let range: NSRange
        let closing: Bool
        let attributes: [Attribute]

        func attribute(_ name: String) -> Attribute? { attributes.first { $0.name == name } }
    }

    static let inlinePairs: Set<String> = ["kbd", "sub", "sup", "b", "strong", "i", "em", "code", "s", "del", "u", "mark"]
    private static let alignValues: Set<String> = ["left", "center", "right", "justify"]

    /// Attributes each tag may carry; a tag with any other attribute is not recognised.
    private static func allowedAttributes(_ name: String) -> Set<String>? {
        switch name {
        case "kbd", "sub", "sup", "b", "strong", "i", "em", "code", "s", "del", "u", "mark", "br",
             "summary", "h1", "h2", "h3", "h4", "h5", "h6": return []
        case "a": return ["href", "title"]
        case "img": return ["src", "alt", "width", "height"]
        case "details": return ["open"]
        case "p", "div": return ["align"]
        default: return nil
        }
    }

    private static func isUnsafeTarget(_ value: String) -> Bool { !LinkSafety.isSafe(value) }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
    private static func isLetter(_ c: unichar) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
    private static func isNameChar(_ c: unichar) -> Bool { isLetter(c) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x5F }

    /// A recognised tag whose `<` is at `i`, within `[i, end)`, or nil.
    static func tag(_ ns: NSString, at i: Int, end: Int) -> Tag? {
        guard i + 2 < end, ns.character(at: i) == 0x3C else { return nil }
        var k = i + 1
        let closing = ns.character(at: k) == 0x2F
        if closing { k += 1 }
        let nameStart = k
        guard k < end, isLetter(ns.character(at: k)) else { return nil }
        while k < end, isNameChar(ns.character(at: k)) { k += 1 }
        let name = ns.substring(with: NSRange(location: nameStart, length: k - nameStart)).lowercased()
        guard let allowed = allowedAttributes(name) else { return nil }

        var attributes: [Attribute] = []
        while true {
            while k < end, isSpace(ns.character(at: k)) { k += 1 }
            guard k < end, k - i < 1000 else { return nil }
            let c = ns.character(at: k)
            if c == 0x3E { k += 1; break }
            if c == 0x2F, k + 1 < end, ns.character(at: k + 1) == 0x3E, !closing { k += 2; break }   // `/>`
            guard !closing, isLetter(c), attributes.count < 8 else { return nil }
            let attrStart = k
            while k < end, isNameChar(ns.character(at: k)) || ns.character(at: k) == 0x3A { k += 1 }
            let attrName = ns.substring(with: NSRange(location: attrStart, length: k - attrStart)).lowercased()
            guard allowed.contains(attrName), !attrName.hasPrefix("on"), attrName != "style" else { return nil }
            var value = ""
            var valueRange = NSRange(location: k, length: 0)
            var look = k
            while look < end, isSpace(ns.character(at: look)) { look += 1 }
            if look < end, ns.character(at: look) == 0x3D {
                look += 1
                while look < end, isSpace(ns.character(at: look)) { look += 1 }
                guard look < end else { return nil }
                let q = ns.character(at: look)
                if q == 0x22 || q == 0x27 {
                    var v = look + 1
                    while v < end, ns.character(at: v) != q {
                        if ns.character(at: v) == 0x3C { return nil }
                        v += 1
                    }
                    guard v < end else { return nil }
                    valueRange = NSRange(location: look + 1, length: v - look - 1)
                    k = v + 1
                } else {
                    var v = look
                    while v < end, !isSpace(ns.character(at: v)), ![0x22, 0x27, 0x3D, 0x3C, 0x3E, 0x60].contains(ns.character(at: v)) { v += 1 }
                    guard v > look else { return nil }
                    valueRange = NSRange(location: look, length: v - look)
                    k = v
                }
                value = ns.substring(with: valueRange)
            }
            attributes.append(Attribute(name: attrName, value: value, valueRange: valueRange))
        }
        let result = Tag(name: name, range: NSRange(location: i, length: k - i), closing: closing, attributes: attributes)

        // Per-tag requirements on attribute values.
        switch name {
        case "a":
            guard !closing else { break }
            guard let href = result.attribute("href"), !href.value.isEmpty, !isUnsafeTarget(href.value) else { return nil }
        case "img":
            guard let src = result.attribute("src"), !src.value.isEmpty, !isUnsafeTarget(src.value) else { return nil }
            for dim in ["width", "height"] {
                if let v = result.attribute(dim)?.value, !isDimension(v) { return nil }
            }
        case "p", "div":
            if let a = result.attribute("align"), !alignValues.contains(a.value.lowercased()) { return nil }
        default: break
        }
        if closing, !attributes.isEmpty { return nil }
        return result
    }

    /// `120`, `120px` or `50%`.
    static func isDimension(_ v: String) -> Bool {
        let digits = v.trimmingCharacters(in: CharacterSet(charactersIn: "px%"))
        return !digits.isEmpty && digits.allSatisfy(\.isNumber) && v.count <= 7
    }

    /// The `</name>` closing the pair opened by `open`, searching from its end, or nil.
    static func closingTag(for open: Tag, _ ns: NSString, end: Int) -> Tag? {
        var i = NSMaxRange(open.range)
        while i + 3 < end {
            if ns.character(at: i) == 0x3C, ns.character(at: i + 1) == 0x2F,
               let t = tag(ns, at: i, end: end), t.closing, t.name == open.name { return t }
            i += 1
        }
        return nil
    }

    // MARK: - Blocks

    enum BlockKind: Equatable {
        case comment
        case detailsTag           // a lone `<details>` / `</details>` line
        case summary              // `<summary>…</summary>` on one line
        case heading(Int)         // `<h1>…</h1>` on one line
        case aligned(String)      // `<p align="…">` … `</p>` (or `<div …>`): alignment only
    }

    struct Block {
        let kind: BlockKind
        let lastLine: Int          // index of the last line of the block (>= first line)
        let markers: [NSRange]     // tag ranges, absolute
        let content: NSRange       // inline content, absolute (empty for comment / details)
    }

    private static func contentEnd(_ ns: NSString, _ line: NSRange) -> Int {
        var e = NSMaxRange(line)
        while e > line.location, ns.character(at: e - 1) == 0x0A || ns.character(at: e - 1) == 0x0D { e -= 1 }
        return e
    }

    /// Failed closer searches within one block-parse pass: a run of unclosed `<!--` or `<p align>` openers
    /// costs one scan, not one each (a failed scan covered every later line too).
    final class Misses {
        var comment: Int?
        var aligned: [String: Int] = [:]
    }

    /// The HTML block starting on `lines[first]`, or nil (the lines stay ordinary text).
    static func block(in ns: NSString, lines: [NSRange], first: Int, misses: Misses = Misses()) -> Block? {
        let line = lines[first]
        let end = contentEnd(ns, line)
        var i = line.location
        var lead = 0
        while i < end, lead < 3, ns.character(at: i) == 0x20 { i += 1; lead += 1 }
        guard i < end, ns.character(at: i) == 0x3C else { return nil }

        if end - i >= 4, ns.substring(with: NSRange(location: i, length: 4)) == "<!--" {
            var k = first
            while k < lines.count {
                if k > first, let miss = misses.comment, first > miss { return nil }
                let from = k == first ? i + 4 : lines[k].location
                let to = contentEnd(ns, lines[k])
                if from <= to, ns.range(of: "-->", options: [], range: NSRange(location: from, length: to - from)).location != NSNotFound {
                    return Block(kind: .comment, lastLine: k, markers: [], content: NSRange(location: i, length: 0))
                }
                k += 1
            }
            misses.comment = misses.comment.map { min($0, first) } ?? first
            return nil
        }

        guard let open = tag(ns, at: i, end: end), !open.closing else {
            // `</details>` alone on its line.
            if let close = tag(ns, at: i, end: end), close.closing, close.name == "details",
                   trailingIsBlank(ns, from: NSMaxRange(close.range), to: end) {
                return Block(kind: .detailsTag, lastLine: first, markers: [close.range], content: NSRange(location: end, length: 0))
            }
            return nil
        }
        let after = NSMaxRange(open.range)
        switch open.name {
        case "details":
            guard trailingIsBlank(ns, from: after, to: end) else { return nil }
            return Block(kind: .detailsTag, lastLine: first, markers: [open.range], content: NSRange(location: end, length: 0))
        case "summary", "h1", "h2", "h3", "h4", "h5", "h6":
            guard let close = closingTag(for: open, ns, end: end),
                  trailingIsBlank(ns, from: NSMaxRange(close.range), to: end) else { return nil }
            let content = NSRange(location: after, length: close.range.location - after)
            let kind: BlockKind = open.name == "summary" ? .summary : .heading(Int(open.name.dropFirst()) ?? 1)
            return Block(kind: kind, lastLine: first, markers: [open.range, close.range], content: content)
        case "p", "div":
            guard let align = open.attribute("align")?.value.lowercased() else { return nil }
            if let close = closingTag(for: open, ns, end: end), trailingIsBlank(ns, from: NSMaxRange(close.range), to: end) {
                return Block(kind: .aligned(align), lastLine: first, markers: [open.range, close.range],
                             content: NSRange(location: after, length: close.range.location - after))
            }
            guard trailingIsBlank(ns, from: after, to: end) else { return nil }
            if let miss = misses.aligned[open.name], first > miss { return nil }
            var k = first + 1
            while k < lines.count {
                let e = contentEnd(ns, lines[k])
                // The first later line that ends with the closing tag ends the block.
                var j = lines[k].location
                while j < e {
                    if ns.character(at: j) == 0x3C, let t = tag(ns, at: j, end: e), t.closing, t.name == open.name,
                       trailingIsBlank(ns, from: NSMaxRange(t.range), to: e) {
                        let start = NSMaxRange(lines[first])
                        return Block(kind: .aligned(align), lastLine: k, markers: [open.range, t.range],
                                     content: NSRange(location: start, length: t.range.location - start))
                    }
                    j += 1
                }
                k += 1
            }
            misses.aligned[open.name] = min(misses.aligned[open.name] ?? first, first)
            return nil
        default:
            return nil
        }
    }

    private static func trailingIsBlank(_ ns: NSString, from: Int, to: Int) -> Bool {
        var i = from
        while i < to { if !isSpace(ns.character(at: i)) { return false }; i += 1 }
        return true
    }

    /// The text alignment (`left` / `center` / `right` / `justify`) of the aligned container enclosing `location`, if any.
    static func enclosingAlignment(of location: Int, in ns: NSString) -> String? {
        var loc = ns.lineRange(for: NSRange(location: location, length: 0)).location
        var steps = 0
        while loc > 0, steps < 60 {
            let line = ns.lineRange(for: NSRange(location: loc - 1, length: 0))
            let end = contentEnd(ns, line)
            var i = line.location
            while i < end, isSpace(ns.character(at: i)) { i += 1 }
            if i < end, ns.character(at: i) == 0x3C, let t = tag(ns, at: i, end: end) {
                if t.closing, t.name == "p" || t.name == "div" { return nil }
                if !t.closing, t.name == "p" || t.name == "div", let a = t.attribute("align") { return a.value.lowercased() }
            }
            loc = line.location
            steps += 1
        }
        return nil
    }
}
