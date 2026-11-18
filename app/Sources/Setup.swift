import AppKit
import SwiftUI
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

/// Reopening last time's windows. macOS drops them when "Close windows when quitting an application"
/// is on, which is its default; an editor is expected to come back as it was left, so the app decides.
enum Session {
    static var reopensWindows: Bool {
        get { UserDefaults.standard.object(forKey: "reopenWindows") == nil || UserDefaults.standard.bool(forKey: "reopenWindows") }
        set {
            UserDefaults.standard.set(newValue, forKey: "reopenWindows")
            apply()
        }
    }

    /// AppKit reads this key, from the app's own settings first, when it decides whether to keep the windows.
    static func apply() { UserDefaults.standard.set(reopensWindows, forKey: "NSQuitAlwaysKeepsWindows") }
}

/// Where a file goes when it is opened while a window is already showing.
enum OpenIn: String, CaseIterable, Identifiable {
    case tab, window

    var id: Self { self }
    var label: String { self == .tab ? "A new tab" : "A new window" }

    static var current: OpenIn { UserDefaults.standard.string(forKey: "openIn").flatMap(OpenIn.init) ?? .tab }

    /// The app's own copy of the system's "Prefer tabs when opening documents"; AppKit looks here first,
    /// but only once per launch. "manual" still lets windows be merged into tabs by hand.
    static func apply() {
        UserDefaults.standard.set(current == .tab ? "always" : "manual", forKey: "AppleWindowTabbingMode")
    }

    /// For one window, so a change made in Settings holds before the next launch too.
    var tabbingMode: NSWindow.TabbingMode {
        self == .tab ? .preferred : NSWindow.userTabbingPreference == .always ? .disallowed : .automatic
    }
}
