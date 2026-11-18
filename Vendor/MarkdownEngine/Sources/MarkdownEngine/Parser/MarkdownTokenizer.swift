//
//  MarkdownTokenizer.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// The token namespace. Tokens are produced by `parseTokensViaAST`
// (`BlockScopedTokenizer`): block structure + block-level tokens come from
// `BlockParser` + `BlockLevelTokenizer` (hand scanners, no regex), inline
// tokens from the AST (`InlineParser` → `InlineASTAdapter`). This file keeps
// only the code-block language helper.
import Foundation

// MARK: - Tokenizer
enum MarkdownTokenizer {

    // MARK: - Code Block Helpers

    static func extractLanguage(from token: MarkdownToken, in text: String) -> String? {
        guard token.kind == .codeBlock,
              let openingMarker = token.markerRanges.first else { return nil }
        let nsText = text as NSString
        guard NSMaxRange(openingMarker) <= nsText.length else { return nil }
        return FenceScanner.language(ofOpenerLine: openingMarker, in: nsText)  // mlisb
    }

    /// mlisb: a fenced block's code with the quote / indentation prefix of each line stripped.
    static func codeText(of token: MarkdownToken, in ns: NSString) -> String {
        guard let open = FenceScanner.opening(ofBlock: token.range, in: ns) else {
            return ns.substring(with: token.contentRange)
        }
        let lines = FenceScanner.body(ofBlock: NSRange(location: token.range.location, length: token.range.length),
                                      in: ns, open: open).lines
        return FenceScanner.strippedCode(lines: lines, in: ns).text
    }
}
