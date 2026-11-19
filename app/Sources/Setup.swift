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

/// Whether last time's windows are still being reopened. AppKit recreates them first and SwiftUI hands
/// each its file a little later; until then a window says so instead of offering a new document.
@MainActor @Observable final class Reopening {
    static let shared = Reopening()

    private(set) var isActive = false
    @ObservationIgnored private var waiting = Set<ObjectIdentifier>()
    @ObservationIgnored private var restored = false
    /// Windows showing a file, so the saved state can say whether there is anything to reopen.
    @ObservationIgnored private var withFiles = Set<ObjectIdentifier>() {
        didSet { if withFiles.isEmpty != oldValue.isEmpty { NSApp.invalidateRestorableState() } }
    }
    private static let key = "mlisb.reopensFiles"

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishRestoringWindowsNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                Reopening.shared.restored = true
                Reopening.shared.settle()
            }
        }
    }

    func encode(_ coder: NSCoder) { coder.encode(!withFiles.isEmpty, forKey: Self.key) }

    /// AppKit decodes the saved state, before any window is recreated, only when there is some.
    func decoded(_ coder: NSCoder) {
        guard Session.reopensWindows, !restored, coder.decodeBool(forKey: Self.key) else { return }
        isActive = true
        // A window saved without a file never gets one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Reopening.shared.isActive = false }
    }

    /// A window without its file yet. Only windows recreated by AppKit are waited for.
    func waiting(_ window: AnyObject) {
        withFiles.remove(ObjectIdentifier(window))
        if isActive, !restored { waiting.insert(ObjectIdentifier(window)) }
    }

    func arrived(_ window: AnyObject) {
        withFiles.insert(ObjectIdentifier(window))
        waiting.remove(ObjectIdentifier(window))
        settle()
    }

    func closed(_ window: AnyObject) {
        withFiles.remove(ObjectIdentifier(window))
        waiting.remove(ObjectIdentifier(window))
        settle()
    }

    private func settle() {
        if restored, waiting.isEmpty, isActive { isActive = false }
    }
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
