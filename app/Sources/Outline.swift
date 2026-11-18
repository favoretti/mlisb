import AppKit
import SwiftUI

struct Heading: Identifiable, Equatable {
    let level: Int
    let title: String
    /// UTF-16 range of the heading line in the document.
    let range: NSRange
    var id: Int { range.location }
}

enum Outline {
    /// ATX headings outside fenced code blocks.
    static func headings(in text: String) -> [Heading] {
        var result: [Heading] = []
        var fence: Character?
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, range, _, _ in
            guard let line else { return }
            let trimmed = line.drop { $0 == " " }
            if let mark = trimmed.first, mark == "`" || mark == "~", trimmed.hasPrefix(String(repeating: mark, count: 3)) {
                if fence == nil { fence = mark } else if fence == mark { fence = nil }
                return
            }
            guard fence == nil else { return }
            let level = trimmed.prefix { $0 == "#" }.count
            let rest = trimmed.dropFirst(level)
            guard (1...6).contains(level), rest.first == " " || rest.isEmpty else { return }
            let title = rest.trimmingCharacters(in: CharacterSet(charactersIn: " #\t"))
            if !title.isEmpty { result.append(Heading(level: level, title: title, range: range)) }
        }
        return result
    }
}

extension Heading {
    /// GitHub-style anchor: lowercase, spaces to dashes, punctuation dropped.
    var slug: String {
        String(title.lowercased().compactMap { c -> Character? in
            c == " " ? "-" : (c.isLetter || c.isNumber || c == "-" || c == "_") ? c : nil
        })
    }
}

struct OutlineView: View {
    let headings: [Heading]
    let jump: (Heading) -> Void

    var body: some View {
        if headings.isEmpty {
            ContentUnavailableView("No headings", systemImage: "list.bullet.indent")
        } else {
            List(headings) { heading in
                Button { jump(heading) } label: {
                    Text(heading.title)
                        .fontWeight(heading.level == 1 ? .semibold : .regular)
                        .foregroundStyle(heading.level > 2 ? .secondary : .primary)
                        .lineLimit(2)
                        .padding(.leading, CGFloat(heading.level - 1) * 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension NSView {
    /// The engine doesn't expose its text view, so find it in the hierarchy.
    func editorTextView() -> NSTextView? {
        if let view = self as? NSTextView, !view.isFieldEditor { return view }
        for subview in subviews {
            if let found = subview.editorTextView() { return found }
        }
        return nil
    }
}
