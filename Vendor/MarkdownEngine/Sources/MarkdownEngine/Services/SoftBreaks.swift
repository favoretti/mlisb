//
//  SoftBreaks.swift
//  MarkdownEngine
//
//  mlisb: the lines of a paragraph are shown joined, as GitHub renders them.
//

import Foundation

/// mlisb: shows the lines of a paragraph joined, as GitHub does, while the editor still holds the
/// file. A joined line break is displayed as U+2005 (a space that allows wrapping), and the next
/// line's indentation and `>` markers as variation selectors, which draw nothing and belong to the
/// space's grapheme. Each swap is one UTF-16 unit for one, so offsets agree between the two forms
/// and the stored text is a pure function of the displayed one.
public enum SoftBreaks {
    /// The stored character a display character stands for, or nil when it stands for itself.
    @inline(__always) static func stored(_ unit: unichar) -> unichar? {
        switch unit {
        case 0x2005: 0x0A
        case 0xFE03: 0x0D
        case 0xFE00: 0x20
        case 0xFE01: 0x09
        case 0xFE02: 0x3E
        default: nil
        }
    }

    @inline(__always) static func shown(_ unit: unichar) -> unichar {
        switch unit {
        case 0x0A: 0x2005
        case 0x0D: 0xFE03
        case 0x20: 0xFE00
        case 0x09: 0xFE01
        default: 0xFE02
        }
    }

    /// Whether `text` can be shown joined: it must not already hold one of the stand-ins.
    public static func applies(to text: String) -> Bool {
        !text.utf16.contains { stored($0) != nil }
    }

    /// The stored form of displayed text.
    public static func storage(_ display: String) -> String {
        guard !applies(to: display) else { return display }
        var units = Array(display.utf16)
        for i in units.indices { if let original = stored(units[i]) { units[i] = original } }
        return String(utf16CodeUnits: units, count: units.count)
    }

    /// `text` with the lines of each paragraph joined; unchanged when it already holds a stand-in.
    static func display(_ text: String, registry: ExtensionRegistry = .empty) -> String {
        guard applies(to: text) else { return text }
        let ns = text as NSString
        let length = ns.length
        guard length > 0 else { return text }
        var units = Array(text.utf16)
        var changed = false

        func lines(in range: NSRange) -> [NSRange] {
            var out: [NSRange] = []
            var at = range.location
            while at < NSMaxRange(range) {
                let line = ns.lineRange(for: NSRange(location: at, length: 0))
                out.append(line)
                at = NSMaxRange(line)
            }
            return out
        }

        /// Joins `line` to `next`: its line break becomes a space, and `next`'s leading
        /// whitespace (and, in a quote, its `>` markers) disappears.
        func join(_ line: NSRange, _ next: NSRange, quote: Bool) {
            var end = NSMaxRange(line)
            guard end > line.location, units[end - 1] == 0x0A, end < length else { return }
            end -= 1
            let crlf = end > line.location && units[end - 1] == 0x0D
            let contentEnd = crlf ? end - 1 : end
            // A hard break: a trailing backslash or two trailing spaces.
            if contentEnd > line.location, units[contentEnd - 1] == 0x5C { return }
            if contentEnd - line.location >= 2, units[contentEnd - 1] == 0x20, units[contentEnd - 2] == 0x20 { return }
            if !startsLikeText(next, quote: quote) { return }
            if crlf { units[end - 1] = shown(0x0D) }
            units[end] = shown(0x0A)
            var i = next.location
            while i < NSMaxRange(next), units[i] == 0x20 || units[i] == 0x09 || (quote && units[i] == 0x3E) {
                units[i] = shown(units[i])
                i += 1
            }
            changed = true
        }

        /// The line's text after its indentation, `>` markers (when `quote`) and list marker (when `listItem`).
        func content(_ line: NSRange, quote: Bool, listItem: Bool = false) -> String {
            var s = Substring(ns.substring(with: line))
            func dropSpace() { s = s.drop { $0 == " " || $0 == "\t" } }
            dropSpace()
            while quote, s.first == ">" { s = s.dropFirst(); dropSpace() }
            if listItem, BlockParser.isListItem(String(s)) {
                s = s.drop { $0 != " " && $0 != "\t" }
                dropSpace()
            }
            return String(s).trimmingCharacters(in: .newlines)
        }

        func quoteDepth(_ line: NSRange) -> Int {
            ns.substring(with: line).prefix { $0 == " " || $0 == "\t" || $0 == ">" }.filter { $0 == ">" }.count
        }

        /// Whether a line's content would read as paragraph text rather than open a block.
        func isText(_ s: String) -> Bool {
            guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            for opener in ["```", "~~~", "$$", "|", "<"] where s.hasPrefix(opener) { return false }
            return !BlockParser.isHeading(s) && !BlockParser.isListItem(s) && !BlockParser.isThematicBreak(s)
        }

        func startsLikeText(_ line: NSRange, quote: Bool) -> Bool { isText(content(line, quote: quote)) }

        let blocks = BlockParser.computeBlocks(text, registry: registry)
        for (index, block) in blocks.enumerated() {
            switch block.kind {
            case .paragraph:
                let own = lines(in: block.range)
                // A paragraph straight after a list item or a quote continues it.
                if index > 0, let last = lines(in: blocks[index - 1].range).last {
                    switch blocks[index - 1].kind {
                    case .list where isText(content(last, quote: false, listItem: true)):
                        join(last, own[0], quote: false)
                    case .blockquote where isText(content(last, quote: true)):
                        join(last, own[0], quote: false)
                    default: break
                    }
                }
                for (line, next) in zip(own, own.dropFirst()) where isText(content(line, quote: false)) {
                    join(line, next, quote: false)
                }
            case .blockquote:
                let own = lines(in: block.range)
                for (line, next) in zip(own, own.dropFirst())
                where quoteDepth(line) == quoteDepth(next) && isText(content(line, quote: true)) {
                    join(line, next, quote: true)
                }
            default:
                break
            }
        }
        return changed ? String(utf16CodeUnits: units, count: units.count) : text
    }
}
