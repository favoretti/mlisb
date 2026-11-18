import AppKit
import WebKit

/// An offscreen web view holding a loaded HTML document.
@MainActor final class Page: NSObject, WKNavigationDelegate {
    let web: WKWebView
    fileprivate let window: NSWindow
    fileprivate var printDone: PrintDone?
    private var loaded: CheckedContinuation<Void, Error>?

    init(html: String, width: CGFloat) async throws {
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 800))
        web.appearance = NSAppearance(named: .aqua)
        // Printing and snapshots need the view to be in a window; it is never shown.
        window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        super.init()
        web.navigationDelegate = self
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loaded = c
            web.loadHTMLString(html, baseURL: nil)
        }
        // d2 diagrams embed their font as a data: URL; capture only once it has loaded.
        _ = try? await web.callAsyncJavaScript("await document.fonts.ready", contentWorld: .page)
    }

    deinit { MainActor.assumeIsolated { window.contentView = nil } }

    static func pdf(_ html: String) async throws -> Data {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        (info.topMargin, info.bottomMargin, info.leftMargin, info.rightMargin) = (54, 54, 54, 54)
        let content = CGSize(width: info.paperSize.width - 108, height: info.paperSize.height - 108)
        let page = try await Page(html: html, width: content.width)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let op = page.web.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = CGRect(origin: .zero, size: content)
        // WebKit lays the pages out asynchronously, so a blocking run() would never finish.
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let done = PrintDone(c)
            op.runModal(for: page.window, delegate: done, didRun: #selector(PrintDone.finished(_:success:contextInfo:)), contextInfo: nil)
            page.printDone = done
        }
        guard ok else { throw RenderError(message: "The PDF could not be created.") }
        return try Data(contentsOf: url)
    }

    static func jpeg(_ html: String) async throws -> Data {
        let page = try await Page(html: html, width: 800)
        let height = (try await page.web.evaluateJavaScript("document.documentElement.scrollHeight") as? Double) ?? 600
        page.web.frame.size.height = height
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: 800, height: height)
        let image = try await page.web.takeSnapshot(configuration: config)
        // The snapshot's pixel size follows the screen's scale; redraw at a fixed 2x on white.
        let w = 1600, h = Int(height * 2)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw RenderError(message: "The image could not be created.") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else { throw RenderError(message: "The image could not be created.") }
        return data
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.resume(); loaded = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { loaded?.resume(throwing: error); loaded = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { loaded?.resume(throwing: error); loaded = nil }
}

// AppKit calls back on its print thread, so this must not be main-actor isolated.
private final class PrintDone: NSObject, @unchecked Sendable {
    let continuation: CheckedContinuation<Bool, Never>
    init(_ c: CheckedContinuation<Bool, Never>) { continuation = c }
    @objc func finished(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) { continuation.resume(returning: success) }
}
