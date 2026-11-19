//
//  NativeTextViewCoordinator+LayoutParagraphs.swift
//  MarkdownEngine
//
//  mlisb: what layout sees of a paragraph differs from the stored text in two ways, both the
//  same length, so every offset still matches the text view's string.
//

import AppKit

extension NativeTextViewCoordinator: NSTextContentStorageDelegate {
    public func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let storage = textContentStorage.textStorage, range.length > 0, NSMaxRange(range) <= storage.length else { return nil }
        var unbreakable: [NSRange] = []
        storage.enumerateAttribute(.unbreakable, in: range) { value, run, _ in
            if value != nil { unbreakable.append(run) }
        }
        let pinned = (textView as? NativeTextView)?.pinnedTextWidth
        let pin = pinned != nil && storage.attribute(.wideBlock, at: range.location, effectiveRange: nil) == nil
        guard pin || !unbreakable.isEmpty else { return nil }

        let paragraph = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        // A hidden link target becomes word joiners: the line can no longer wrap between a link's
        // text and its punctuation, which would start the next line with a lone `)`.
        for run in unbreakable {
            paragraph.replaceCharacters(in: NSRange(location: run.location - range.location, length: run.length),
                                        with: String(repeating: "\u{2060}", count: run.length))
        }
        // Ordinary text keeps the column's width; a positive tail indent is measured from the leading edge.
        if pin, let width = pinned {
            let whole = NSRange(location: 0, length: paragraph.length)
            paragraph.enumerateAttribute(.paragraphStyle, in: whole) { value, run, _ in
                let style = (value as? NSParagraphStyle) ?? .default
                guard style.tailIndent <= 0 else { return }
                let held = style.mutableCopy() as! NSMutableParagraphStyle
                held.tailIndent = max(1, width + style.tailIndent)
                paragraph.addAttribute(.paragraphStyle, value: held, range: run)
            }
        }
        return NSTextParagraph(attributedString: paragraph)
    }
}
