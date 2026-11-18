//
//  GFMInline.swift
//  MarkdownEngine
//
//  mlisb: inline recognition for reference-style links and images, footnote
//  references, and a safe subset of raw HTML. Matches surface in the inline AST
//  as extension-shaped nodes (`InlineNode.ext`) under the reserved `gfm.` id
//  namespace — like directives, so marker shrink, caret reveal, token
//  projection and rich copy apply unchanged.
//

import Foundation

enum GFMInline {

    static let idPrefix = "gfm."
    static let refID = "gfm.ref"             // [text][label] · [label][] · [label]
    static let refImageID = "gfm.refimage"   // ![alt][label]
    static let footnoteID = "gfm.footnote"   // [^id]

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
    private static let backslash: unichar = 0x5C

    /// A construct opening at `i`, or nil (the characters stay literal).
    static func match(_ ns: NSString, _ len: Int, at i: Int, registry: ExtensionRegistry) -> Match? {
        let c = ns.character(at: i)
        if c == lbracket, let refs = registry.references { return reference(ns, len, start: i, image: false, refs) }
        if c == 0x21, i + 1 < len, ns.character(at: i + 1) == lbracket, let refs = registry.references {
            return reference(ns, len, start: i, image: true, refs)
        }
        return nil
    }

    // MARK: - References and footnotes

    /// First unescaped `]` at bracket depth zero from `from`, or nil.
    private static func closingBracket(_ ns: NSString, _ len: Int, from: Int) -> Int? {
        var depth = 0
        var k = from
        while k < len {
            let c = ns.character(at: k)
            if c == backslash { k += 2; continue }
            if c == lbracket { depth += 1 } else if c == rbracket {
                if depth == 0 { return k }
                depth -= 1
            }
            k += 1
        }
        return nil
    }

    private static func reference(_ ns: NSString, _ len: Int, start i: Int, image: Bool, _ refs: ReferenceTable) -> Match? {
        let open = image ? i + 1 : i
        let textStart = open + 1
        guard let closeText = closingBracket(ns, len, from: textStart), closeText > textStart else { return nil }
        let textRange = NSRange(location: textStart, length: closeText - textStart)
        let text = ns.substring(with: textRange)

        if !image, ns.character(at: textStart) == 0x5E {   // [^id]
            let id = ns.substring(with: NSRange(location: textStart + 1, length: textRange.length - 1))
            guard !id.isEmpty, !id.contains(where: { $0.isWhitespace }),
                  refs.footnotes.contains(ReferenceTable.normalize(id)) else { return nil }
            return Match(id: footnoteID, range: NSRange(location: i, length: closeText + 1 - i),
                         contentRange: NSRange(location: textStart + 1, length: textRange.length - 1),
                         markers: [NSRange(location: i, length: 2), NSRange(location: closeText, length: 1)],
                         parsesContent: false, target: nil)
        }

        var label = text
        var end = closeText + 1
        if end < len, ns.character(at: end) == 0x28 { return nil }          // an inline link's `(`
        if end < len, ns.character(at: end) == lbracket {                    // [text][label] / [text][]
            var k = end + 1
            while k < len, ns.character(at: k) != rbracket {
                let c = ns.character(at: k)
                if c == lbracket { return nil }
                k += c == backslash ? 2 : 1
            }
            guard k < len else { return nil }
            if k > end + 1 { label = ns.substring(with: NSRange(location: end + 1, length: k - end - 1)) }
            end = k + 1
        }
        guard let def = refs.links[ReferenceTable.normalize(label)] else { return nil }
        return Match(id: image ? refImageID : refID, range: NSRange(location: i, length: end - i),
                     contentRange: textRange,
                     markers: [NSRange(location: i, length: image ? 2 : 1),
                               NSRange(location: closeText, length: end - closeText)],
                     parsesContent: !image, target: def.target)
    }
}
