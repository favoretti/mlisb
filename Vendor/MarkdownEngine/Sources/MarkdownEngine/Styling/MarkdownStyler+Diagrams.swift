//
//  MarkdownStyler+Diagrams.swift
//  MarkdownEngine
//
//  mlisb: fenced code blocks (```mermaid, ```d2) drawn as images.
//

import AppKit
import Foundation

extension MarkdownStyler {

    /// Same mechanism as block LaTeX: the image replaces the collapsed source
    /// unless the caret is inside the block. Runs after the AST styler, so these
    /// attributes win over the code-block styling.
    static func styleDiagramFences(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.scoped(StylingContext.indexed(ctx.tokens, .codeBlock)) {
            guard !ctx.activeTokenIndices.contains(idx), token.markerRanges.count == 2 else { continue }
            let openLine = ctx.nsText.substring(with: token.markerRanges[0])
            let language = FenceScanner.language(ofOpenerLine: token.markerRanges[0], in: ctx.nsText)?
                .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            let source = MarkdownTokenizer.codeText(of: token, in: ctx.nsText)   // prefixes stripped
            guard !language.isEmpty,
                  !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let image = ctx.services.diagrams.image(language: language, source: source),
                  image.size.width > 0, image.size.height > 0
            else { continue }

            // shortcut: fitted to the width at styling time, so it only refits on the
            // next restyle; hook into the table width-change path if resizing matters.
            let scale = min(1, effectiveContainerWidth(for: ctx) / image.size.width)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rendered = appendRenderedStandaloneBlock(
                for: token,
                rawContent: source,
                image: image,
                imageBounds: CGRect(origin: .zero, size: size),
                paragraphSpacingBefore: ctx.configuration.blockLatex.paragraphSpacingBefore,
                paragraphSpacing: ctx.configuration.blockLatex.paragraphSpacing,
                alignment: .center,
                mode: .collapsedSource(markerTexts: [openLine, ctx.nsText.substring(with: token.markerRanges[1])]),
                ctx: ctx,
                attrs: &attrs
            )
            // The layout fragment fills any paragraph that carries the code background.
            if rendered { attrs.append((token.range, [.backgroundColor: NSColor.clear])) }
        }
        return attrs
    }
}
