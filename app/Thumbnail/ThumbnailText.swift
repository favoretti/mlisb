import Foundation

/// What a thumbnail shows of a markdown file: a title and the lines after it, as plain text.
enum ThumbnailText {
    static let maxBytes = 32 * 1024

    static func select(from markdown: String, maxBody: Int = 60) -> (title: String?, body: [String]) {
        var lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { ["---", "..."].contains($0.trimmingCharacters(in: .whitespaces)) }) {
            lines.removeSubrange(...end)
        }
        var fence: String?
        var text: [(line: String, heading: Bool)] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let marker = ["```", "~~~"].first(where: line.hasPrefix) {
                fence = fence == nil ? marker : (fence == marker ? nil : fence)
                continue
            }
            guard fence == nil, !line.isEmpty, !line.allSatisfy({ "-*_=| :".contains($0) }) else { continue }
            let heading = line.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil
            text.append((strip(line), heading))
        }
        let cleaned = text.filter { !$0.line.isEmpty }
        guard let index = cleaned.firstIndex(where: \.heading) ?? cleaned.indices.first else { return (nil, []) }
        return (cleaned[index].line, cleaned[(index + 1)...].prefix(maxBody).map(\.line))
    }

    private static func strip(_ line: String) -> String {
        var s = line
        for (pattern, template) in [
            (#"^(#{1,6}|>)+\s*"#, ""), (#"^([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?"#, ""),
            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"), (#"[`*~]|(?<![A-Za-z0-9])_|_(?![A-Za-z0-9])"#, ""),
        ] {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
