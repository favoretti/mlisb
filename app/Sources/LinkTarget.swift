import Foundation

/// What a clicked markdown link points at. Targets come from the document, which
/// may be untrusted.
enum LinkTarget: Equatable {
    /// A heading in the same document, as a lowercase slug.
    case anchor(String)
    /// Anything with a URL scheme (web, mail, another app): leaves mlisb, so ask first.
    case url(URL)
    /// A local file, resolved against the document's folder. Never launched.
    case file(URL)

    init(_ link: String, from document: URL) {
        if link.hasPrefix("#") {
            self = .anchor(link.dropFirst().lowercased())
        } else if let url = URL(string: link), let scheme = url.scheme, scheme.lowercased() != "file" {
            self = .url(url)
        } else {
            let path = String(link.dropFirst(link.lowercased().hasPrefix("file://") ? 7 : 0).prefix { $0 != "#" })
            self = .file(URL(fileURLWithPath: path.removingPercentEncoding ?? path,
                             relativeTo: document.deletingLastPathComponent()).standardizedFileURL)
        }
    }
}
