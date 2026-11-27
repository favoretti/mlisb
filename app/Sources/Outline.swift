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

extension NSTextView {
    /// Selects `range` and scrolls it into view. The text is laid out lazily, so lay it all out first:
    /// until then a heading far down has no position to scroll to.
    /// Scrolls the clip view itself: `scrollToVisible` stops at the engine's container view and moves nothing.
    func reveal(_ range: NSRange) {
        window?.makeFirstResponder(self)
        setSelectedRange(range)
        guard let tlm = textLayoutManager, let scrollView = enclosingScrollView else { return scrollRangeToVisible(range) }
        tlm.ensureLayout(for: tlm.documentRange)
        guard let location = tlm.location(tlm.documentRange.location, offsetBy: range.location) else { return }
        // The range's own lines: a fragment is a whole paragraph or block, which can start far above.
        let end = tlm.location(location, offsetBy: range.length) ?? location
        var lines = CGRect.null
        tlm.enumerateTextSegments(in: NSTextRange(location: location, end: end) ?? NSTextRange(location: location),
                                  type: .standard, options: []) { _, frame, _, _ in
            lines = lines.union(frame)
            return true
        }
        guard !lines.isNull else { return }
        let clip = scrollView.contentView
        var target = convert(lines.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y), to: clip)
        target.size.height = min(target.height, clip.bounds.height / 2)
        let visible = clip.bounds
        let context = min(80, visible.height / 4)
        guard target.minY - context < visible.minY || target.maxY + context > visible.maxY else { return }
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - visible.height)
        clip.scroll(to: NSPoint(x: visible.origin.x, y: min(max(0, target.minY - context), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }
}
