import AppKit
import Foundation
import MarkdownEngine

public enum ExportFormat: String, CaseIterable, Sendable { case html, pdf, jpeg, epub }

@MainActor public enum Exporter {
    /// Complete standalone HTML document: inline CSS, diagrams as inline SVG, local images inlined.
    public static func html(markdown: String, title: String, baseURL: URL?) async -> String {
        let body = await body(markdown, baseURL: baseURL) { language, source in
            guard let d = try? await RenderService.shared.render(language, source: source, theme: .light),
                  !d.svg.lowercased().contains("<script") else { return nil }
            return "<div class=\"diagram\">\(d.svg)</div>"
        }
        // The CSP is a second line of defence: nothing in the document can run script or load subresources but images.
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: http: https:; font-src data:; style-src 'unsafe-inline'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>\(css)</style></head><body><main>
        \(body)
        </main></body></html>
        """
    }

    /// File contents for an export format.
    public static func data(_ format: ExportFormat, markdown: String, title: String, baseURL: URL?) async throws -> Data {
        switch format {
        case .html:
            return Data(await html(markdown: markdown, title: title, baseURL: baseURL).utf8)
        case .pdf:
            return try await Page.pdf(await html(markdown: markdown, title: title, baseURL: baseURL))
        case .jpeg:
            return try await Page.jpeg(await html(markdown: markdown, title: title, baseURL: baseURL))
        case .epub:
            return try await epub(markdown: markdown, title: title, baseURL: baseURL)
        }
    }

    /// For "Copy as Rich Text".
    public static func attributedString(markdown: String, baseURL: URL?) async -> NSAttributedString {
        let body = await body(markdown, baseURL: baseURL) { _, _ in nil }
        let doc = "<html><head><meta charset=\"utf-8\"><style>\(css)</style></head><body>\(body)</body></html>"
        return (try? NSAttributedString(data: Data(doc.utf8),
                                        options: [.documentType: NSAttributedString.DocumentType.html,
                                                  .characterEncoding: String.Encoding.utf8.rawValue],
                                        documentAttributes: nil)) ?? NSAttributedString(string: markdown)
    }

    /// For "Copy as Plain Text": the readable text without markdown syntax.
    public static func plainText(markdown: String) async -> String {
        await attributedString(markdown: markdown, baseURL: nil).string
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Body

    /// Markdown to an HTML fragment. `diagram` returns the replacement for a mermaid/d2 block, or nil to keep the code.
    static func body(_ markdown: String, baseURL: URL?,
                     diagram: (DiagramLanguage, String) async -> String?) async -> String {
        var html = MarkdownHTMLRenderer.html(from: markdown, extensions: [StrikethroughExtension()])
        // The renderer escapes all text, so this exact markup can only come from a fenced block.
        html = await replacing(html, #"<pre><code class="language-(mermaid|d2)">(.*?)</code></pre>"#) { g in
            guard let language = DiagramLanguage(rawValue: g[0]) else { return nil }
            return await diagram(language, unescape(g[1]))
        }
        html = await replacing(html, #"<img src="([^"]*)""#) { g in
            let source = unescape(g[0])
            guard LinkSafety.isSafe(source) else { return "<img src=\"#\"" }
            guard let uri = dataURI(source, baseURL: baseURL) else { return nil }
            return "<img src=\"\(uri)\""
        }
        // A second check at the export boundary; the renderer already refuses these targets.
        return await replacing(html, #"href="([^"]*)""#) { g in
            LinkSafety.isSafe(unescape(g[0])) ? nil : "href=\"#\""
        }
    }

    private static let imageTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                     "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp"]

    private static func dataURI(_ src: String, baseURL: URL?) -> String? {
        guard let baseURL, !src.hasPrefix("/"), URL(string: src)?.scheme == nil else { return nil }
        let url = baseURL.appendingPathComponent(src.removingPercentEncoding ?? src)
        guard let type = imageTypes[url.pathExtension.lowercased()], let data = try? Data(contentsOf: url) else { return nil }
        return "data:\(type);base64,\(data.base64EncodedString())"
    }

    /// Replaces each match with the closure's result (given the capture groups); nil keeps the match.
    private static func replacing(_ s: String, _ pattern: String,
                                  _ f: ([String]) async -> String?) async -> String {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let ns = s as NSString
        var out = s as NSString
        var results: [(NSRange, String)] = []
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let groups = (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            if let r = await f(groups) { results.append((m.range, r)) }
        }
        for (range, r) in results.reversed() { out = out.replacingCharacters(in: range, with: r) as NSString }
        return out as String
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
    }

    static let css = """
    :root{color-scheme:light}
    body{margin:0;background:#fff;color:#1d1d1f;font:16px/1.6 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    main{max-width:44em;margin:0 auto;padding:2em 1.25em}
    h1,h2,h3,h4,h5,h6{line-height:1.25;margin:1.6em 0 .5em;break-after:avoid}
    h1{font-size:2em;border-bottom:1px solid #d2d2d7;padding-bottom:.2em}h2{font-size:1.5em}h3{font-size:1.25em}
    a{color:#0066cc}img,svg{max-width:100%;height:auto}
    code,pre{font:.9em ui-monospace,SFMono-Regular,Menlo,monospace}
    code{background:#f2f2f4;padding:.1em .3em;border-radius:4px}
    pre{background:#f2f2f4;padding:.8em 1em;border-radius:6px;overflow-x:auto;white-space:pre-wrap;break-inside:avoid}
    pre code{background:none;padding:0}
    blockquote{margin:1em 0;padding:.1em 1em;border-left:4px solid #d2d2d7;color:#555}
    table{border-collapse:collapse;margin:1em 0;break-inside:avoid}
    th,td{border:1px solid #d2d2d7;padding:.4em .8em;text-align:left}th{background:#f2f2f4}
    hr{border:0;border-top:1px solid #d2d2d7;margin:2em 0}
    li input{margin-right:.4em}.diagram{text-align:center;margin:1em 0;break-inside:avoid}
    @media screen and (prefers-color-scheme:dark){
    :root{color-scheme:dark}
    body{background:#1c1c1e;color:#f5f5f7}h1,hr,th,td,blockquote{border-color:#48484a}
    a{color:#64acff}code,pre,th{background:#2c2c2e}blockquote{color:#aeaeb2}
    .diagram{background:#fff;border-radius:6px;padding:.5em}}
    @media print{main{max-width:none;padding:0}body{font-size:11pt}}
    """
}
