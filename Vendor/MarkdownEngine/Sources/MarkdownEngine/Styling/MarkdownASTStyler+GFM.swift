//
//  MarkdownASTStyler+GFM.swift
//  MarkdownEngine
//
//  mlisb: styling for GitHub Flavored Markdown constructs beyond CommonMark.
//

import AppKit
import Foundation

extension MarkdownASTStyler {

    // MARK: - Alerts

    enum AlertKind: CaseIterable {
        case note, tip, important, warning, caution

        init?(marker: String) {
            guard let kind = Self.allCases.first(where: { "[!\($0.name.uppercased())]" == marker.uppercased() }) else { return nil }
            self = kind
        }

        var name: String { "\(self)" }
        var title: String { name.prefix(1).uppercased() + name.dropFirst() }

        /// Dynamic system colours: they follow light and dark appearance.
        var color: NSColor {
            switch self {
            case .note: return .systemBlue
            case .tip: return .systemGreen
            case .important: return .systemPurple
            case .warning: return .systemOrange
            case .caution: return .systemRed
            }
        }
    }

    /// The alert a blockquote block opens with: a single `>` and `[!NOTE]` (etc.) alone on the first line.
    static func alertOpening(inBlockquote range: NSRange, ns: NSString) -> (kind: AlertKind, marker: NSRange)? {
        let line = NSIntersectionRange(ns.lineRange(for: NSRange(location: range.location, length: 0)), range)
        var i = line.location
        let end = NSMaxRange(line)
        var lead = 0
        while i < end, lead < 3, ns.character(at: i) == 0x20 { i += 1; lead += 1 }
        guard i < end, ns.character(at: i) == 0x3E else { return nil }
        i += 1
        if i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        while i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        var stop = end
        while stop > i, [0x0A, 0x0D, 0x20, 0x09].contains(ns.character(at: stop - 1)) { stop -= 1 }
        let marker = NSRange(location: i, length: stop - i)
        guard marker.length >= 6, marker.length <= 12,
              let kind = AlertKind(marker: ns.substring(with: marker)) else { return nil }
        return (kind, marker)
    }

    /// One line of an alert: the bar takes the alert colour; on the first line the marker text is
    /// replaced by the bold title unless the caret is on that line.
    static func styleAlertLine(kind: AlertKind, marker: NSRange, isFirst: Bool, tokenRange: NSRange,
                               ctx: Ctx, into attrs: inout [StyledRange]) {
        attrs.append((tokenRange, [.blockquoteBarColor: kind.color]))
        guard isFirst else { return }
        if ctx.isActive(tokenRange) {
            attrs.append((marker, [.foregroundColor: kind.color]))
        } else {
            attrs.append((marker, [.foregroundColor: NSColor.clear, .alertTitle: kind.title]))
        }
    }

    /// Ranges the incomplete-link bracket pass must leave alone (`[!NOTE]` and the like).
    static func gfmExcludedRanges(in blocks: [BlockNode], ns: NSString) -> [NSRange] {
        var out: [NSRange] = []
        for block in blocks {
            if case .blockquote(let range, _) = block, let alert = alertOpening(inBlockquote: range, ns: ns) {
                out.append(alert.marker)
            }
        }
        return out
    }
}
