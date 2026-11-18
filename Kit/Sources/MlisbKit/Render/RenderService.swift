import Foundation
import WebKit

@MainActor
public final class RenderService: NSObject, WKNavigationDelegate {
    public static let shared = RenderService()

    private var webView: WKWebView?
    private var loaded: CheckedContinuation<Void, Error>?
    private var tail: Task<Void, Never>?
    private let cache = NSCache<NSString, Box>()

    private final class Box { let value: RenderedDiagram; init(_ v: RenderedDiagram) { value = v } }

    public func render(_ language: DiagramLanguage, source: String, theme: DiagramTheme) async throws -> RenderedDiagram {
        let key = "\(language.rawValue)\u{0}\(theme.rawValue)\u{0}\(source)" as NSString
        if let hit = cache.object(forKey: key) { return hit.value }

        // Renders share one DOM stage, so run them strictly one after another.
        let previous = tail
        let job = Task {
            await previous?.value
            return try await self.perform(language, source, theme)
        }
        tail = Task { _ = try? await job.value }
        let result = try await job.value
        cache.setObject(Box(result), forKey: key)
        return result
    }

    private func perform(_ language: DiagramLanguage, _ source: String, _ theme: DiagramTheme) async throws -> RenderedDiagram {
        let web = try await page()
        let value: Any?
        do {
            value = try await web.callAsyncJavaScript(
                // The module script can still be running when didFinish fires.
                "while (!window.mlisb) await new Promise(r => setTimeout(r, 20)); return await window.mlisb.render(lang, source, theme)",
                arguments: ["lang": language.rawValue, "source": source, "theme": theme.rawValue],
                contentWorld: .page)
        } catch let error as NSError {
            let message = error.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            throw RenderError(message: message)
        }
        guard let dict = value as? [String: Any], let svg = dict["svg"] as? String,
              let w = (dict["width"] as? NSNumber)?.doubleValue, let h = (dict["height"] as? NSNumber)?.doubleValue
        else { throw RenderError(message: "Renderer returned an unexpected result") }

        let size = CGSize(width: w, height: h)
        web.frame = CGRect(origin: .zero, size: size)
        let config = WKPDFConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        let pdf = try await web.pdf(configuration: config)
        return RenderedDiagram(svg: svg, pdf: pdf, size: size)
    }

    private func page() async throws -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        let root = Bundle.module.resourceURL!.appendingPathComponent("render")
        config.setURLSchemeHandler(RenderSchemeHandler(root: root), forURLScheme: RenderSchemeHandler.scheme)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loaded = c
            web.load(URLRequest(url: URL(string: "\(RenderSchemeHandler.scheme)://app/index.html")!))
        }
        webView = web
        return web
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume(); loaded = nil
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        self.webView = nil  // recreated on the next render
        loaded?.resume(throwing: RenderError(message: "The diagram renderer stopped unexpectedly.")); loaded = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        loaded?.resume(throwing: error); loaded = nil
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        loaded?.resume(throwing: error); loaded = nil
    }
}
