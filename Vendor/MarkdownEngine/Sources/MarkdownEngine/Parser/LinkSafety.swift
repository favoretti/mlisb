//
//  LinkSafety.swift
//  MarkdownEngine
//
//  mlisb: which link and image targets may become active markup.
//

import Foundation

public enum LinkSafety {
    /// True for relative targets and for http, https and mailto URLs; everything else
    /// (javascript:, data:, file:, app schemes) is refused. Browsers ignore whitespace and
    /// control characters inside a scheme, so they are removed before the scheme is read.
    public static func isSafe(_ target: String) -> Bool {
        var cleaned = String.UnicodeScalarView()
        cleaned.append(contentsOf: target.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F })
        let text = String(cleaned).lowercased()
        guard let colon = text.firstIndex(of: ":") else { return true }
        let scheme = text[..<colon]
        // A character reference could hide a scheme from this check if the value were ever decoded again.
        if scheme.contains("&#") { return false }
        // A colon after `/`, `?` or `#` belongs to a path, query or fragment, not a scheme.
        if scheme.contains(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { return true }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }
}
