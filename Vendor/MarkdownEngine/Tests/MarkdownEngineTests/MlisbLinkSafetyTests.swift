import Testing
@testable import MarkdownEngine

@Suite("mlisb link safety")
struct MlisbLinkSafetyTests {
    @Test("relative targets and web or mail URLs are safe")
    func safe() {
        for target in ["https://example.com/a?b=1", "HTTP://EXAMPLE.COM", "mailto:a@b.c", "./notes.md", "../a/b.png",
                       "#anchor", "/abs/path", "notes.md", "a/b:c.md", "page?time=10:30", "x#frag:ment", ""] {
            #expect(LinkSafety.isSafe(target), "\(target)")
        }
    }

    @Test("script, data, file and app schemes are refused, however they are disguised")
    func unsafe() {
        for target in ["javascript:alert(1)", "JaVaScRiPt:alert(1)", " javascript:alert(1)", "java\tscript:alert(1)",
                       "java\nscript:alert(1)", "\u{01}javascript:alert(1)", "javascript\u{7F}:alert(1)",
                       "vbscript:x", "data:text/html,<script>alert(1)</script>", "file:///etc/passwd",
                       "x-app://do", "jav&#x09;ascript:alert(1)"] {
            #expect(!LinkSafety.isSafe(target), "\(target)")
        }
    }

    @Test("the HTML export never emits a refused address", arguments: [
        "[x](javascript:alert(1))", "[x](java\tscript:alert(1))", "![x](javascript:alert(1))",
        "[x][r]\n\n[r]: javascript:alert(1)\n", "[x](data:text/html,hi)",
        "<a href=\"javascript:alert(1)\">x</a>", "<img src=\"javascript:alert(1)\">",
    ])
    func export(markdown: String) {
        let html = MarkdownHTMLRenderer.html(from: markdown)
        for attribute in ["href=\"", "src=\""] {
            var rest = html[...]
            while let start = rest.range(of: attribute) {
                let value = rest[start.upperBound...].prefix { $0 != "\"" }
                #expect(LinkSafety.isSafe(String(value)), "\(attribute)\(value) in \(html)")
                rest = rest[start.upperBound...]
            }
        }
    }
}
