import MlisbKit
import SwiftUI

extension View {
    /// Change marks over the editor and the history sheet.
    func reviewUI(_ document: Document) -> some View { modifier(ReviewModifier(document: document)) }
}

private struct ReviewModifier: ViewModifier {
    @Bindable var document: Document

    func body(content: Content) -> some View {
        content
            .background(ReviewHost(changes: document.review.changes))
            .sheet(isPresented: $document.showingHistory) { HistoryView(document: document) }
    }
}

extension Document {
    /// Selects the next or previous change in the focused editor and scrolls it into view, wrapping around.
    func step(forward: Bool) {
        guard let textView = NSApp.keyWindow?.contentView?.editorTextView() else { return }
        let location = textView.selectedRange().location
        guard let change = forward ? review.next(after: location) : review.previous(before: location) else { return }
        let range = change.range.clamped(to: (textView.string as NSString).length)
        textView.reveal(range)
        current = change
    }
}

private extension NSRange {
    func clamped(to length: Int) -> NSRange {
        let l = min(location, length)
        return NSRange(location: l, length: min(self.length, length - l))
    }
}

/// Version History in the toolbar; the review controls are in `ReviewBar`.
struct ReviewToolbar: ToolbarContent {
    let document: Document

    var body: some ToolbarContent {
        if !document.isBundled {
            ToolbarItem {
                Button { document.showingHistory = true } label: { Label("Version History", systemImage: "clock.arrow.circlepath") }
                    .help("Version History (⌃⌘H)")
            }
        }
    }
}

extension TextChange.Kind {
    static let allKinds: [TextChange.Kind] = [.added, .modified, .removed]

    var word: String {
        switch self {
        case .added: "added"
        case .modified: "changed"
        case .removed: "removed"
        }
    }

    var color: Color {
        switch self {
        case .added: .green
        case .modified: .orange
        case .removed: .red
        }
    }
}

/// What the bar says: where the reader is among the changes, or how many there are, and what the
/// selected change replaced.
struct ReviewBarText: Equatable {
    var position: String
    var detail: String?

    init(changes: [TextChange], current: TextChange?) {
        guard let current, let i = changes.firstIndex(of: current) else {
            let counts = TextChange.Kind.allKinds.map { kind in (kind, changes.filter { $0.kind == kind }.count) }
            position = counts.filter { $0.1 > 0 }.map { "\($0.1) \($0.0.word)" }.joined(separator: " · ")
            detail = nil
            return
        }
        position = "Change \(i + 1) of \(changes.count) · \(current.kind.word)"
        let old = current.oldText.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        switch current.kind {
        case .added: detail = nil
        case .modified: detail = old.isEmpty ? nil : "Was: “\(old.prefix(300))”"
        case .removed: detail = "Removed: “\(old.prefix(300))”"
        }
    }
}

/// A strip like a status bar across the top of the editor while the file has unreviewed changes.
/// Always the same height, so stepping through changes doesn't move the text.
struct ReviewBar: View {
    let document: Document

    var body: some View {
        let changes = document.review.changes
        if !changes.isEmpty {
            let current = document.currentChange
            let text = ReviewBarText(changes: changes, current: current)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Button { document.step(forward: false) } label: { Image(systemName: "chevron.up").frame(width: 14) }
                            .help("Previous Change (⌥⌘↑)")
                            .accessibilityLabel("Previous Change")
                        Button { document.step(forward: true) } label: { Image(systemName: "chevron.down").frame(width: 14) }
                            .help("Next Change (⌥⌘↓)")
                            .accessibilityLabel("Next Change")
                    }
                    Circle().fill(current?.kind.color ?? .secondary).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(text.position).monospacedDigit().fixedSize()
                    if let detail = text.detail {
                        Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    Button("Mark Reviewed") { document.markCurrentReviewed() }
                        .disabled(current == nil)
                        .help(current == nil ? "Step to a change first (⌥⌘↓)" : "Mark this change reviewed and go to the next (⌥⌘R)")
                    Button("Mark All Reviewed") { document.markReviewed() }
                        .help("Mark every change reviewed (⇧⌥⌘R)")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 4))
                .padding(.horizontal, 10)
                .frame(height: 30)
                Divider()
            }
            .background(.bar)
        }
    }
}

struct ReviewCommands: Commands {
    @FocusedValue(\.document) private var document

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu("Review") {
                Group {
                    Button("Next Change") { document?.step(forward: true) }
                        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    Button("Previous Change") { document?.step(forward: false) }
                        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    Button("Mark Reviewed") { document?.markCurrentReviewed() }
                        .keyboardShortcut("r", modifiers: [.command, .option])
                        .disabled(document?.currentChange == nil)
                    Button("Mark All Reviewed") { document?.markReviewed() }
                        .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                }
                .disabled(document?.review.changes.isEmpty != false)
                Button("Version History…") { document?.showingHistory = true }
                    .keyboardShortcut("h", modifiers: [.control, .command])
                    .disabled(document == nil || document?.isBundled == true)
            }
        }
    }
}

// MARK: Overlay

/// Finds the editor's text view and keeps a pass-through overlay on it.
private struct ReviewHost: NSViewRepresentable {
    let changes: [TextChange]

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> ReviewOverlay { ReviewOverlay() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.changes = changes
        context.coordinator.attach(from: view)
    }
}

final class ReviewOverlay: EditorOverlay {
    var changes: [TextChange] = [] { didSet { needsDisplay = true } }

    /// Left edge of the change bars, just left of the text.
    static func barX(_ textOrigin: NSPoint) -> CGFloat { max(2, textOrigin.x - 8) }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView, let layout = textView.textLayoutManager, let content = layout.textContentManager else { return }
        let string = textView.string as NSString
        let origin = textView.textContainerOrigin

        func rects(_ range: NSRange) -> [CGRect] {
            guard range.length > 0,
                  let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { return [] }
            var out: [CGRect] = []
            layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
                out.append(frame.offsetBy(dx: origin.x, dy: origin.y))
                return true
            }
            return out
        }
        // The segment of a trailing newline would stretch to the margin.
        func trimmed(_ range: NSRange) -> NSRange {
            var r = range.clamped(to: string.length)
            while r.length > 1, [10, 13].contains(string.character(at: NSMaxRange(r) - 1)) { r.length -= 1 }
            return r
        }

        let barX = Self.barX(origin)
        for change in changes {
            switch change.kind {
            case .removed:
                let at = min(change.range.location, string.length)
                guard at > 0 || string.length > 0 else { continue }
                let y: CGFloat?
                if at < string.length {
                    y = rects(NSRange(location: at, length: 1)).first?.minY
                } else {
                    y = rects(NSRange(location: at - 1, length: 1)).last?.maxY
                }
                guard let y else { continue }
                NSColor.systemRed.setFill()
                NSRect(x: barX, y: y - 1, width: 8, height: 2).fill()
            case .added, .modified:
                let color = change.kind == .added ? NSColor.systemGreen : NSColor.systemOrange
                let block = rects(trimmed(change.range))
                guard let top = block.map(\.minY).min(), let bottom = block.map(\.maxY).max() else { continue }
                color.setFill()
                NSRect(x: barX, y: top, width: 3, height: bottom - top).fill()
                color.withAlphaComponent(0.18).setFill()
                let tinted = change.kind == .modified && !change.wordRanges.isEmpty
                    ? change.wordRanges.flatMap { rects($0.clamped(to: string.length)) } : block
                tinted.forEach { $0.fill() }
            }
        }
    }
}
