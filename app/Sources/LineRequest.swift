import AppKit
import Observation

/// A request, sent by the command-line tool, to put the caret at the start of a line.
struct LineRequest: Equatable {
    let file: URL
    let line: Int
    /// Distinguishes a repeat of the same request.
    let id = UUID()

    /// Parses `mlisb://line?file=<absolute path>&line=<n>`; anything malformed is ignored.
    init?(url: URL) {
        guard url.scheme == "mlisb", url.host == "line",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let path = items.first(where: { $0.name == "file" })?.value, path.hasPrefix("/"),
              let line = items.first(where: { $0.name == "line" })?.value.flatMap({ Int($0) }), line >= 1
        else { return nil }
        file = URL(fileURLWithPath: path)
        self.line = line
    }

    /// UTF-16 offset where `line` (1-based) starts; a line past the end gives the last line.
    static func offset(ofLine line: Int, in text: String) -> Int {
        let ns = text as NSString
        var location = 0
        for _ in 1..<max(line, 1) {
            let end = NSMaxRange(ns.lineRange(for: NSRange(location: location, length: 0)))
            if end >= ns.length { break }
            location = end
        }
        return location
    }

    func matches(_ other: URL) -> Bool { file.standardizedFileURL.path == other.standardizedFileURL.path }
}

/// The request waiting for its window; an editor showing the file takes it.
@MainActor @Observable final class LineRequests {
    static let shared = LineRequests()
    var pending: LineRequest?
}

/// Takes `mlisb://` events before SwiftUI does, so one never opens a window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handle(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string), let request = LineRequest(url: url) else { return }
        MainActor.assumeIsolated { LineRequests.shared.pending = request }
    }
}
