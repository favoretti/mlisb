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
            .navigationSubtitle(reviewSubtitle(document.review.counts))
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

/// The window subtitle while there are changes, e.g. "2 added · 1 removed"; empty hides it.
func reviewSubtitle(_ counts: (added: Int, modified: Int, removed: Int)) -> String {
    [(counts.added, "added"), (counts.modified, "changed"), (counts.removed, "removed")]
        .filter { $0.0 > 0 }
        .map { "\($0.0) \($0.1)" }
        .joined(separator: " · ")
}

/// The review controls in the window's toolbar, beside the table of contents. The counts are the
/// window's subtitle.
struct ReviewToolbar: ToolbarContent {
    let document: Document

    var body: some ToolbarContent {
        if !document.review.changes.isEmpty {
            ToolbarItemGroup {
                Button { document.step(forward: false) } label: { Label("Previous Change", systemImage: "chevron.up") }
                    .help("Previous Change (⌥⌘↑)")
                Button { document.step(forward: true) } label: { Label("Next Change", systemImage: "chevron.down") }
                    .help("Next Change (⌥⌘↓)")
                Button { document.markReviewed() } label: { Label("Mark Reviewed", systemImage: "checkmark").labelStyle(.titleAndIcon) }
                    .help("Clear the change marks (⌥⌘R)")
            }
            // macOS 26 merges neighbouring items into one glass capsule; keep this group apart.
            if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
        }
        if !document.isBundled {
            ToolbarItem {
                Button { document.showingHistory = true } label: { Label("Version History", systemImage: "clock.arrow.circlepath") }
                    .help("Version History (⌃⌘H)")
            }
        }
    }
}

/// What a removal took out, while the selected change is one; the margin only shows where.
/// Floats over the editor so stepping on and off a removal doesn't move the text; `reveal` keeps
/// 80pt clear below the change, more than this takes.
struct RemovedNote: View {
    let document: Document

    var body: some View {
        if let current = document.current, current.kind == .removed, document.review.changes.contains(current) {
            HStack(spacing: 6) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                Text("Removed: “\(current.oldText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))”")
                    .lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .padding(.horizontal, 24).padding(.bottom, 12)
            .allowsHitTesting(false)
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
                    Button("Mark Reviewed") { document?.markReviewed() }
                        .keyboardShortcut("r", modifiers: [.command, .option])
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
