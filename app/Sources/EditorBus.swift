import MarkdownEngine
import SwiftUI

/// Notification names for one editor. The engine's handlers listen app-wide, so
/// each editor gets its own names and menu commands reach only the focused one.
struct EditorBus: Equatable {
    let id: String

    func name(_ action: String) -> Notification.Name { Notification.Name("mlisb.\(id).\(action)") }

    func post(_ action: String, _ info: [String: Any]? = nil) {
        NotificationCenter.default.post(name: name(action), object: nil, userInfo: info)
    }

    var engineBus: MarkdownEditorBus {
        MarkdownEditorBus(
            applyBoldRequest: name("bold"),
            applyItalicRequest: name("italic"),
            applyHeadingRequest: name("heading"),
            applyStrikethroughRequest: name("strikethrough"),
            applyInlineCodeRequest: name("code"),
            applyBlockquoteRequest: name("quote"),
            applyUnorderedListRequest: name("bullets"),
            applyOrderedListRequest: name("numbers"),
            applyLinkRequest: name("link"),
            applyCodeBlockRequest: name("codeBlock"),
            findClearHighlights: name("findClear"),
            findQuery: name("findQuery"),
            findResults: name("findResults")
        )
    }
}

extension FocusedValues {
    @Entry var editorBus: EditorBus?
}

struct FormatCommands: Commands {
    @FocusedValue(\.editorBus) private var bus

    var body: some Commands {
        CommandMenu("Format") {
            Group {
                Button("Bold") { bus?.post("bold") }.keyboardShortcut("b")
                Button("Italic") { bus?.post("italic") }.keyboardShortcut("i")
                Button("Strikethrough") { bus?.post("strikethrough") }.keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Inline Code") { bus?.post("code") }.keyboardShortcut("e")
                Button("Link") { bus?.post("link") }.keyboardShortcut("k")
                Divider()
                ForEach(1...3, id: \.self) { level in
                    Button("Heading \(level)") { bus?.post("heading", ["level": level]) }
                        .keyboardShortcut(KeyEquivalent(Character("\(level)")))
                }
                Divider()
                Button("Bulleted List") { bus?.post("bullets") }
                Button("Numbered List") { bus?.post("numbers") }
                Button("Quote") { bus?.post("quote") }
                Button("Code Block") { bus?.post("codeBlock") }
            }
            .disabled(bus == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") { bus?.post("showFind") }.keyboardShortcut("f").disabled(bus == nil)
        }
    }
}
