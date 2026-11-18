import AppKit
import UniformTypeIdentifiers

/// Whether Markdown files open with mlisb, and making it so.
@MainActor enum DefaultApp {
    private static let types = ["net.daringfireball.markdown", "net.favoretti.mlisb.markdown-extra"].compactMap { UTType($0) }

    static var isDefault: Bool {
        types.allSatisfy { type in
            NSWorkspace.shared.urlForApplication(toOpen: type).flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle.main.bundleIdentifier
        }
    }

    static func makeDefault() async throws {
        for type in types { try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) }
    }
}

/// Where the `mlisb` command is installed, if anywhere.
enum CommandLineTool {
    static var installedPath: String? {
        ["/usr/local/bin/mlisb", "/opt/homebrew/bin/mlisb"].first { FileManager.default.fileExists(atPath: $0) }
    }
}

/// A new document is a file from the start: ask where it goes, then create it empty.
@MainActor func createNewDocument() -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Untitled.md"
    panel.allowedContentTypes = UTType(filenameExtension: "md").map { [$0] } ?? []
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    do { try Data().write(to: url) } catch {
        NSAlert(error: error).runModal()
        return nil
    }
    return url
}
