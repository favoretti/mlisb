import Foundation

/// What the preview shows of a file: its text (maybe cut) or a reason it can't.
enum PreviewContent: Equatable {
    case text(String, truncated: Bool)
    case notUTF8

    static let maxBytes = 1_048_576

    static func load(_ url: URL) throws -> PreviewContent {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        let truncated = data.count > maxBytes
        // A cut in the middle of a character is trimmed; anything else not UTF-8 is rejected.
        let head = data.prefix(maxBytes)
        guard let text = (0...(truncated ? 3 : 0)).lazy.compactMap({ String(data: head.dropLast($0), encoding: .utf8) }).first
        else { return .notUTF8 }
        return .text(text, truncated: truncated)
    }
}
