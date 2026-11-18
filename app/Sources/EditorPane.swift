import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex
import SwiftUI

struct EditorPane: View {
    @Bindable var document: Document
    /// Shows a file inside the current workspace; false if it isn't part of it.
    var showInWorkspace: (URL) -> Bool = { _ in false }
    @AppStorage("sourceMode") private var sourceMode = false
    @AppStorage("showOutline") private var showOutline = false
    @AppStorage("textSize") private var textSize = ReadingSettings.defaultSize
    @AppStorage("lineWidth") private var lineWidth = LineWidth.medium
    @State private var showFind = false
    @Environment(\.openWindow) private var openWindow

    private var bus: EditorBus { EditorBus(id: document.url.path) }

    var body: some View {
        // Read here so a finished diagram render re-runs the editor update.
        let _ = DiagramStore.shared.version
        GeometryReader { geometry in
            editor(width: geometry.size.width)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                banner
                if showFind { FindBar(bus: bus, isPresented: $showFind) }
            }
        }
        .inspector(isPresented: $showOutline) {
            OutlineView(headings: Outline.headings(in: document.text), jump: jump)
                .inspectorColumnWidth(min: 160, ideal: 220, max: 400)
        }
        .toolbar {
            Toggle(isOn: $showOutline) { Label("Table of Contents", systemImage: "list.bullet.indent") }
        }
        .focusedSceneValue(\.editorBus, bus)
        .focusedSceneValue(\.document, document)
        .reviewUI(document)
        .onReceive(NotificationCenter.default.publisher(for: bus.name("showFind"))) { _ in showFind = true }
        .onChange(of: LineRequests.shared.pending, initial: true) { _, request in
            if let request, request.matches(document.url) { apply(request) }
        }
        .onDisappear { document.save() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            document.save()
        }
    }

    private static let latex = SwiftMathBridge()

    private func editor(width: CGFloat) -> NativeTextViewWrapper {
        var config = MarkdownEditorConfiguration.default
        config.services.syntaxHighlighter = HighlightJSBridge()
        config.services.diagrams = Diagrams()
        config.services.images = LocalImages(folder: document.url.deletingLastPathComponent())
        config.services.bus = bus.engineBus
        config.services.latex = Self.latex
        config.extensions = [StrikethroughExtension()]
        config.revealAllSyntax = sourceMode
        // A centered column of at most the chosen width that shrinks with the pane. (The engine's
        // own readingWidth is a fixed width and clips in a narrow window.)
        config.textInsets = TextInsets(horizontal: ReadingSettings.sideInset(paneWidth: width, width: lineWidth), vertical: 12)
        // Nothing may change what the user typed.
        config.lists.arrowReplacementEnabled = false
        config.spellChecking.automaticQuoteSubstitution = false
        config.spellChecking.automaticSpellingCorrection = false

        var editor = NativeTextViewWrapper(
            text: $document.text,
            configuration: config,
            fontSize: CGFloat(ReadingSettings.clamp(textSize)),
            documentId: document.url.path,
            isEditable: !document.isReadOnly
        )
        editor.onOpenLink = { open(link: $0) }
        return editor
    }

    private func jump(to heading: Heading) {
        guard let textView = NSApp.keyWindow?.contentView?.editorTextView(),
              let index = Outline.headings(in: document.text).firstIndex(of: heading)
        else { return }
        // The editor's text can differ from the file's (shortened wiki links), so
        // take the same heading's position from what is displayed.
        let displayed = Outline.headings(in: textView.string)
        guard displayed.indices.contains(index) else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: displayed[index].range.location, length: 0))
        textView.scrollRangeToVisible(displayed[index].range)
    }

    /// The editor's text view appears a moment after the pane, so wait for it.
    private func apply(_ request: LineRequest) {
        LineRequests.shared.pending = nil
        Task {
            for _ in 0..<40 {
                // The window may not be key yet; the one showing this file's text is the target.
                let textViews = NSApp.windows.compactMap { $0.contentView?.editorTextView() }
                if let textView = textViews.first(where: { $0.string == document.text && !document.text.isEmpty })
                    ?? NSApp.keyWindow?.contentView?.editorTextView(),
                   !textView.string.isEmpty || document.text.isEmpty {
                    let at = NSRange(location: LineRequest.offset(ofLine: request.line, in: textView.string), length: 0)
                    textView.window?.makeFirstResponder(textView)
                    textView.setSelectedRange(at)
                    // The text is laid out lazily; lay it all out so the target has a position to scroll to.
                    if let tlm = textView.textLayoutManager {
                        tlm.ensureLayout(for: tlm.documentRange)
                        if let loc = tlm.location(tlm.documentRange.location, offsetBy: at.location),
                           let fragment = tlm.textLayoutFragment(for: loc) { textView.scrollToVisible(fragment.layoutFragmentFrame.insetBy(dx: 0, dy: -80)) }
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func open(link: String) -> Bool {
        switch LinkTarget(link, from: document.url) {
        case .anchor(let slug):
            if let heading = Outline.headings(in: document.text).first(where: { $0.slug == slug }) { jump(to: heading) }
        case .url(let url):
            if confirmOpening(url) { NSWorkspace.shared.open(url) }
        case .file(let target):
            if showInWorkspace(target) { break }
            if FS.markdown.contains(target.pathExtension.lowercased()) {
                openWindow(value: target)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([target])
            }
        }
        return true
    }

    private func confirmOpening(_ url: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Open this link?"
        alert.informativeText = url.absoluteString
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @ViewBuilder private var banner: some View {
        if let error = document.error {
            HStack {
                Label(error, systemImage: "exclamationmark.triangle")
                Spacer()
                if document.needsAccess { Button("Grant Access…", action: grantAccess) }
            }
            .padding(8).background(.red.opacity(0.15))
        } else if document.conflictingDiskText != nil {
            HStack {
                Text("This file changed on disk while you were editing.")
                Spacer()
                Button("Keep Mine") { document.resolveConflict(keepMine: true) }
                Button("Load Theirs") { document.resolveConflict(keepMine: false) }
            }
            .padding(8).background(.yellow.opacity(0.15))
        }
    }
}

extension EditorPane {
    /// The sandbox only extends to what the user picks, so ask for the folder.
    private func grantAccess() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = document.url.deletingLastPathComponent()
        panel.prompt = "Grant Access"
        panel.message = "mlisb needs access to this folder to open the file."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Access.shared.begin(folder)
        document.reload()
    }
}

/// Markdown images whose paths are relative to the document's folder.
struct LocalImages: EmbeddedImageProvider {
    let folder: URL

    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        guard !reference.name.contains("://"), let path = reference.name.removingPercentEncoding else { return nil }
        return NSImage(contentsOf: URL(fileURLWithPath: path, relativeTo: folder))
    }

    func fingerprint() -> AnyHashable { folder }
}

private struct FindBar: View {
    let bus: EditorBus
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var count = 0
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { step(1) }
            if !query.isEmpty {
                Text(count == 0 ? "No results" : "\(index + 1) of \(count)")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Button { step(-1) } label: { Image(systemName: "chevron.up") }.disabled(count == 0)
            Button { step(1) } label: { Image(systemName: "chevron.down") }.disabled(count == 0)
            Button("Done") { isPresented = false }.keyboardShortcut(.cancelAction)
        }
        .padding(8)
        .background(.bar)
        .onAppear { focused = true }
        .onDisappear { bus.post("findClear") }
        .onChange(of: query) {
            index = 0
            search()
        }
        .onReceive(NotificationCenter.default.publisher(for: bus.name("findResults"))) { note in
            count = note.userInfo?["count"] as? Int ?? 0
        }
    }

    private func search() { bus.post("findQuery", ["query": query, "currentIndex": index]) }

    private func step(_ delta: Int) {
        guard count > 0 else { return }
        index = (index + delta + count) % count
        search()
    }
}
