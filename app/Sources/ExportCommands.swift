import MlisbKit
import SwiftUI
import UniformTypeIdentifiers

extension FocusedValues {
    @Entry var document: Document?
}

/// File > Export and Edit > Copy as, for the focused document.
struct ExportCommands: Commands {
    @FocusedValue(\.document) private var document

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Menu("Export") {
                Button("HTML…") { export(.html, "html") }
                Button("PDF…") { export(.pdf, "pdf") }
                Button("JPEG…") { export(.jpeg, "jpg") }
                Button("ePub…") { export(.epub, "epub") }
            }
            .disabled(document == nil)
        }
        CommandGroup(after: .pasteboard) {
            Menu("Copy as") {
                Button("Plain Text") { copy { [.string: Data(await Exporter.plainText(markdown: $0.text).utf8)] } }
                Button("Rich Text") {
                    copy { document in
                        let rich = await Exporter.attributedString(markdown: document.text, baseURL: document.folder)
                        let all = NSRange(location: 0, length: rich.length)
                        return [.rtf: rich.rtf(from: all) ?? Data(), .string: Data(rich.string.utf8)]
                    }
                }
                Button("Markdown") { copy { [.string: Data($0.text.utf8)] } }
                Button("HTML") {
                    copy { document in
                        let html = Data(await Exporter.html(markdown: document.text, title: document.title, baseURL: document.folder).utf8)
                        return [.html: html, .string: html]
                    }
                }
            }
            .disabled(document == nil)
        }
    }

    private func export(_ format: ExportFormat, _ fileExtension: String) {
        guard let document else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(document.title).\(fileExtension)"
        panel.allowedContentTypes = UTType(filenameExtension: fileExtension).map { [$0] } ?? []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await Exporter.data(format, markdown: document.text, title: document.title, baseURL: document.folder)
                    .write(to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func copy(_ make: @escaping @MainActor (Document) async -> [NSPasteboard.PasteboardType: Data]) {
        guard let document else { return }
        Task {
            let items = await make(document)
            NSPasteboard.general.clearContents()
            for (type, data) in items { NSPasteboard.general.setData(data, forType: type) }
        }
    }
}

extension Document {
    var folder: URL { url.deletingLastPathComponent() }
    var title: String { url.deletingPathExtension().lastPathComponent }
}
