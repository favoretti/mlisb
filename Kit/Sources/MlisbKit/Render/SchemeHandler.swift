import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves only files under the bundled `render` directory.
final class RenderSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mlisb-render"
    let root: URL

    init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    /// Maps a URL path to a file inside `root`, or nil if it escapes or doesn't exist.
    static func resolve(_ path: String, in root: URL) -> URL? {
        let rel = path.removingPercentEncoding ?? path
        guard !rel.split(separator: "/").contains("..") else { return nil }
        let file = root.appendingPathComponent(rel).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"),
              (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        else { return nil }
        return file
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url,
              let file = Self.resolve(url.path, in: root),
              let data = try? Data(contentsOf: file)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = switch file.pathExtension {
        case "wasm": "application/wasm"
        case "js", "mjs": "text/javascript"
        case "html": "text/html"
        case "css": "text/css"
        case "json": "application/json"
        default: UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
