import Foundation
import Testing
@testable import MlisbKit

@MainActor
@Suite(.serialized)
struct RenderTests {
    let service = RenderService.shared

    func check(_ d: RenderedDiagram) {
        #expect(String(decoding: d.pdf.prefix(4), as: UTF8.self) == "%PDF")
        #expect(d.size.width > 20 && d.size.width < 5000)
        #expect(d.size.height > 20 && d.size.height < 5000)
        #expect(d.svg.contains("<svg"))
    }

    @Test func mermaidFlowchart() async throws {
        check(try await service.render(.mermaid, source: "flowchart LR\n A[Start] --> B{Ok?}\n B --> C[Done]", theme: .light))
    }

    /// Labels with line breaks, edge labels and class styles: drawn as SVG text, not HTML that would
    /// make the output unreadable as XML.
    @Test func mermaidLabelsWithLineBreaks() async throws {
        let source = """
        flowchart LR
          a["one<br/>two"] --> b{"three<br>four"}
          b -- "yes" --> c["five"]
          classDef ok fill:#e6f4ea,stroke:#34a853,color:#111;
          class c ok;
        """
        let d = try await service.render(.mermaid, source: source, theme: .dark)
        check(d)
        #expect(!d.svg.contains("foreignObject"))
        #expect(d.svg.contains("one") && d.svg.contains("two") && d.svg.contains("four"))
    }

    @Test func mermaidSequence() async throws {
        check(try await service.render(.mermaid, source: "sequenceDiagram\n Alice->>Bob: Hi\n Bob-->>Alice: Hello", theme: .light))
    }

    @Test func d2Basic() async throws {
        check(try await service.render(.d2, source: "x -> y", theme: .light))
    }

    @Test func lightDiffersFromDark() async throws {
        for (lang, src) in [(DiagramLanguage.mermaid, "flowchart LR\n A --> B"), (.d2, "x -> y")] {
            let l = try await service.render(lang, source: src, theme: .light)
            let d = try await service.render(lang, source: src, theme: .dark)
            #expect(l.svg != d.svg)
        }
    }

    @Test func invalidSourceThrowsThenRecovers() async throws {
        for (lang, bad, good) in [(DiagramLanguage.mermaid, "flowchart LR\n A --> --> ((", "flowchart LR\n A --> B"),
                                  (.d2, "x -> {", "x -> y")] {
            do {
                _ = try await service.render(lang, source: bad, theme: .light)
                Issue.record("expected \(lang) error")
            } catch let e as RenderError {
                #expect(!e.message.isEmpty)
            }
            check(try await service.render(lang, source: good, theme: .light))
        }
    }

    @Test func concurrentRendersAreIndependent() async throws {
        let jobs: [(DiagramLanguage, String, String)] = [
            (.mermaid, "flowchart LR\n A1[alpha] --> B1[one]", "alpha"),
            (.mermaid, "flowchart LR\n A2[bravo] --> B2[two]", "bravo"),
            (.mermaid, "sequenceDiagram\n charlie->>delta: hi", "charlie"),
            (.d2, "echo -> foxtrot", "echo"),
            (.d2, "golf -> hotel", "golf"),
            (.d2, "india -> juliet", "india"),
        ]
        let tasks = jobs.map { job in
            Task { try await service.render(job.0, source: job.1, theme: .light) }
        }
        var results: [RenderedDiagram] = []
        for t in tasks { results.append(try await t.value) }
        for (i, job) in jobs.enumerated() {
            check(results[i])
            #expect(results[i].svg.contains(job.2))
        }
    }

    @Test func remoteIconStillRenders() async throws {
        check(try await service.render(.d2, source: "x: {icon: https://example.invalid/i.png}\nx -> y", theme: .light))
    }

    @Test func schemeHandlerRejectsTraversal() throws {
        let root = Bundle.module.resourceURL!.appendingPathComponent("render")
        #expect(RenderSchemeHandler.resolve("/index.html", in: root) != nil)
        for bad in ["/../Package.swift", "/%2e%2e/x", "/a/../../x", "/..", "/missing.js", "/"] {
            #expect(RenderSchemeHandler.resolve(bad, in: root) == nil, "\(bad)")
        }
    }
}
