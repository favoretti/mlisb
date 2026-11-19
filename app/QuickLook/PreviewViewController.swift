import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import QuickLookUI
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() { view = NSView() }

    func preparePreviewOfFile(at url: URL) async throws {
        let content = try PreviewContent.load(url)
        let host = NSHostingView(rootView: PreviewView(content: content))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
    }
}

struct PreviewView: View {
    let content: PreviewContent

    var body: some View {
        switch content {
        case .notUTF8:
            Text("This file is not UTF-8 text, so it can't be previewed.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .text(let text, let truncated):
            VStack(spacing: 0) {
                if truncated {
                    Text("Preview truncated: showing the first 1 MB.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(6).background(.bar)
                }
                Self.editor(text)
            }
        }
    }

    static func editor(_ text: String) -> NativeTextViewWrapper {
        var editor = NativeTextViewWrapper(
            text: .constant(text), configuration: configuration, documentId: "preview", isEditable: false)
        // A preview can't ask before opening, so it follows no links.
        editor.onOpenLink = { _ in true }
        return editor
    }

    static var configuration: MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default
        config.services.syntaxHighlighter = HighlightJSBridge()
        // The preview fills the Quick Look window, so widening it widens the text, tables and code.
        config.textInsets = TextInsets(horizontal: 28, vertical: 12)
        return config
    }
}
