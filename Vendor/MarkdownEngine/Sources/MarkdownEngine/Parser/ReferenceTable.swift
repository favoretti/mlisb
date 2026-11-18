//
//  ReferenceTable.swift
//  MarkdownEngine
//
//  mlisb: link reference definitions (`[label]: target "title"`) and footnote
//  definitions (`[^id]: text`). Each definition is one line and its own block;
//  the table resolves `[text][label]`, `[label][]`, `[label]`, `![alt][label]`
//  and `[^id]` during the inline pass, so an undefined label stays text.
//

import Foundation

struct ReferenceTable {
    struct Definition: Equatable {
        let target: String
        let title: String?
    }

    var links: [String: Definition] = [:]
    var footnotes: Set<String> = []

    /// Labels match case-insensitively with internal whitespace collapsed (CommonMark).
    static func normalize(_ label: String) -> String {
        label.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    /// Table of every definition block in `blocks` (first definition of a label wins); nil when there are none.
    init?(blocks: [Block], ns: NSString) {
        for block in blocks {
            switch block.kind {
            case .linkDefinition:
                guard let def = Self.linkDefinition(in: ns, line: block.range) else { continue }
                let key = Self.normalize(def.label)
                if links[key] == nil { links[key] = Definition(target: def.target, title: def.title) }
            case .footnoteDefinition:
                if let marker = Self.footnoteMarker(in: ns, line: block.range) {
                    footnotes.insert(Self.normalize(ns.substring(with: marker.id)))
                }
            default: break
            }
        }
        if links.isEmpty && footnotes.isEmpty { return nil }
    }

    /// Where the caret goes for a footnote reference: the start of the text of its `[^id]:` definition.
    static func footnoteDefinitionLocation(id: String, in ns: NSString) -> Int? {
        let wanted = normalize(id)
        var loc = 0
        while loc < ns.length {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            if let found = footnoteMarker(in: ns, line: line), normalize(ns.substring(with: found.id)) == wanted {
                var p = NSMaxRange(found.marker)
                let end = contentEnd(ns, line)
                while p < end, isSpace(ns.character(at: p)) { p += 1 }
                return p
            }
            loc = NSMaxRange(line)
        }
        return nil
    }

    /// Whether any line of `range` is a link or footnote definition (an edit there restyles every use).
    static func touchesDefinition(in ns: NSString, range: NSRange) -> Bool {
        var loc = range.location
        while loc < NSMaxRange(range) {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            if linkDefinition(in: ns, line: line) != nil || footnoteMarker(in: ns, line: line) != nil { return true }
            loc = NSMaxRange(line)
        }
        return false
    }

    // MARK: - Line scanners

    private static func contentEnd(_ ns: NSString, _ line: NSRange) -> Int {
        var e = NSMaxRange(line)
        while e > line.location, ns.character(at: e - 1) == 0x0A || ns.character(at: e - 1) == 0x0D { e -= 1 }
        return e
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }

    /// `[label]: target "title"` on one line, up to 3 spaces of indent.
    static func linkDefinition(in ns: NSString, line: NSRange) -> (label: String, target: String, title: String?)? {
        let end = contentEnd(ns, line)
        var i = line.location
        var lead = 0
        while i < end, lead < 3, ns.character(at: i) == 0x20 { i += 1; lead += 1 }
        guard i < end, ns.character(at: i) == 0x5B else { return nil }
        i += 1
        let labelStart = i
        while i < end, ns.character(at: i) != 0x5D {
            let c = ns.character(at: i)
            if c == 0x5B { return nil }
            i += (c == 0x5C && i + 1 < end) ? 2 : 1
        }
        guard i < end, i > labelStart else { return nil }
        let label = ns.substring(with: NSRange(location: labelStart, length: i - labelStart))
        guard label.first != "^", !label.allSatisfy({ $0.isWhitespace }) else { return nil }
        i += 1
        guard i < end, ns.character(at: i) == 0x3A else { return nil }
        i += 1
        while i < end, isSpace(ns.character(at: i)) { i += 1 }
        guard i < end else { return nil }

        let target: String
        if ns.character(at: i) == 0x3C {   // <destination>
            var j = i + 1
            while j < end, ns.character(at: j) != 0x3E, ns.character(at: j) != 0x3C { j += 1 }
            guard j < end, ns.character(at: j) == 0x3E else { return nil }
            target = ns.substring(with: NSRange(location: i + 1, length: j - i - 1))
            i = j + 1
        } else {
            var j = i
            while j < end, !isSpace(ns.character(at: j)) { j += 1 }
            target = ns.substring(with: NSRange(location: i, length: j - i))
            i = j
        }
        guard !target.isEmpty || ns.character(at: i - 1) == 0x3E else { return nil }

        let afterTarget = i
        while i < end, isSpace(ns.character(at: i)) { i += 1 }
        if i == end { return (label, target, nil) }
        guard i > afterTarget else { return nil }          // the title needs a separating space
        let open = ns.character(at: i)
        let close: unichar = open == 0x28 ? 0x29 : open
        guard open == 0x22 || open == 0x27 || open == 0x28 else { return nil }
        var last = end
        while last > i, isSpace(ns.character(at: last - 1)) { last -= 1 }
        guard last - i >= 2, ns.character(at: last - 1) == close else { return nil }
        return (label, target, ns.substring(with: NSRange(location: i + 1, length: last - i - 2)))
    }

    /// `[^id]:` at the start of a line (up to 3 spaces of indent): the id and the marker through the colon.
    static func footnoteMarker(in ns: NSString, line: NSRange) -> (id: NSRange, marker: NSRange)? {
        let end = contentEnd(ns, line)
        var i = line.location
        var lead = 0
        while i < end, lead < 3, ns.character(at: i) == 0x20 { i += 1; lead += 1 }
        let start = i
        guard i + 2 < end, ns.character(at: i) == 0x5B, ns.character(at: i + 1) == 0x5E else { return nil }
        i += 2
        let idStart = i
        while i < end, ns.character(at: i) != 0x5D {
            let c = ns.character(at: i)
            if isSpace(c) || c == 0x5B { return nil }
            i += 1
        }
        guard i < end, i > idStart, i + 1 < end, ns.character(at: i + 1) == 0x3A else { return nil }
        return (NSRange(location: idStart, length: i - idStart), NSRange(location: start, length: i + 2 - start))
    }
}
