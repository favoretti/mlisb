//
//  MarkdownASTStyler+GFM.swift
//  MarkdownEngine
//
//  mlisb: styling for GitHub Flavored Markdown constructs beyond CommonMark.
//

import AppKit
import Foundation

extension MarkdownASTStyler {

    // MARK: - Front matter

    /// Quiet metadata: monospaced, dimmed, never parsed for markdown. The source is always shown, so the
    /// caret and source mode change nothing.
    static func styleFrontMatter(range: NSRange, ctx: Ctx, into attrs: inout [StyledRange]) {
        var block = range
        while block.length > 0, [0x0A, 0x0D].contains(ctx.ns.character(at: NSMaxRange(block) - 1)) { block.length -= 1 }
        guard block.length > 0 else { return }
        let lineHeight = ceil(ctx.codeFont.ascender - ctx.codeFont.descender + ctx.codeFont.leading)
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = lineHeight
        para.maximumLineHeight = lineHeight
        para.lineBreakMode = .byCharWrapping
        let last = NSMutableParagraphStyle()
        last.setParagraphStyle(para)
        last.paragraphSpacing = ctx.baseParagraphSpacing
        attrs.append((ctx.ns.paragraphRange(for: block), [.paragraphStyle: para]))
        attrs.append((ctx.ns.lineRange(for: NSRange(location: NSMaxRange(block) - 1, length: 0)), [.paragraphStyle: last]))
        attrs.append((block, [.font: ctx.codeFont, .foregroundColor: ctx.theme.mutedText, .spellingState: 0]))
        // The two `---` fence lines sit a step quieter than the metadata between them.
        let quiet = ctx.theme.mutedText.withAlphaComponent(0.6)
        let open = ctx.ns.lineRange(for: NSRange(location: block.location, length: 0))
        let close = ctx.ns.lineRange(for: NSRange(location: NSMaxRange(block) - 1, length: 0))
        attrs.append((open, [.foregroundColor: quiet]))
        attrs.append((close, [.foregroundColor: quiet]))
    }

    // MARK: - Setext headings

    /// A heading whose single marker is an underline line (`=`/`-`) rather than an ATX `#` run.
    static func isSetextUnderline(_ markers: [NSRange], _ ns: NSString) -> Bool {
        guard let marker = markers.first, markers.count == 1, marker.length > 0 else { return false }
        return ns.character(at: marker.location) != 0x23
    }

    /// The underline is dimmed and small until the caret is in the heading (or source mode is on); the
    /// text lines above it close up to it.
    static func styleSetextUnderline(_ underline: NSRange, range: NSRange, headingPara: NSParagraphStyle,
                                     ctx: Ctx, into attrs: inout [StyledRange]) {
        let active = ctx.isActive(range)
        let size = active ? ctx.baseFont.pointSize : max(6, round(ctx.baseFont.pointSize * 0.5))
        let font = NSFont(name: ctx.fontName, size: size) ?? .systemFont(ofSize: size)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)

        let textPara = headingPara.mutableCopy() as! NSMutableParagraphStyle
        textPara.paragraphSpacing = 0
        let textRange = NSRange(location: range.location, length: underline.location - range.location)
        if textRange.length > 0 { attrs.append((ctx.ns.paragraphRange(for: textRange), [.paragraphStyle: textPara])) }

        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = lineHeight
        para.maximumLineHeight = lineHeight
        para.paragraphSpacingBefore = 0
        para.paragraphSpacing = headingPara.paragraphSpacing
        attrs.append((ctx.ns.paragraphRange(for: underline), [.paragraphStyle: para]))
        attrs.append((underline, [.font: font, .foregroundColor: ctx.theme.mutedText]))
    }

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
            if case .frontMatter(let range) = block { out.append(range) }
        }
        return out
    }
}
