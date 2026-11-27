import MlisbKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct MlisbApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("sourceMode") private var sourceMode = false
    @AppStorage("showOutline") private var showOutline = false
    @AppStorage("showLineNumbers") private var showLineNumbers = false
    @AppStorage("textSize") private var textSize = ReadingSettings.defaultSize
    @AppStorage("inspectorTab") private var inspectorTab = InspectorTab.contents

#if canImport(Sparkle)
    @StateObject private var updater = UpdaterModel()
#endif

    init() {
        Session.apply()
        _ = Reopening.shared
        OpenIn.apply()
    }

    var body: some Scene {
        // The window's value is its workspace root: a folder or a single file.
        WindowGroup(for: URL.self) { $root in
            WorkspaceView(root: $root)
        }
        .defaultSize(width: 1100, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { OpenCommand() }
            CommandGroup(replacing: .help) { HelpCommand() }
            CommandGroup(after: .appInfo) {
#if canImport(Sparkle)
                CheckForUpdatesCommand(updater: updater)
#endif
                Button("Install Command Line Tool…") { showInstallCommandLineTool() }
            }
            CommandGroup(before: .sidebar) {
                Toggle("Source Mode", isOn: $sourceMode).keyboardShortcut("/")
                Toggle("Line Numbers", isOn: $showLineNumbers).keyboardShortcut("l", modifiers: [.command, .option])
                Toggle("Table of Contents", isOn: Binding(
                    get: { showOutline }, set: { showOutline = $0; if $0 { inspectorTab = .contents } })).keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("Bigger") { textSize = ReadingSettings.step(textSize, by: 1) }.keyboardShortcut("+")
                Button("Smaller") { textSize = ReadingSettings.step(textSize, by: -1) }.keyboardShortcut("-")
                Button("Actual Size") { textSize = ReadingSettings.defaultSize }.keyboardShortcut("0")
                Divider()
            }
            SidebarCommands()
            FormatCommands()
            NavigationCommands()
            ReviewCommands()
            ExportCommands()
        }
#if canImport(Sparkle)
        Settings { SettingsView(updater: updater) }
#else
        Settings { SettingsView() }
#endif
    }
}

private struct OpenCommand: View {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workspaceRoot) private var focusedRoot

    var body: some View {
        Button("New Document…") { if let url = createNewDocument() { open([url]) } }
            .keyboardShortcut("n")
        Button("Open…") { open(chooseFilesOrFolders()) }
            .keyboardShortcut("o")
        Menu("Open Recent") {
            ForEach(Access.shared.recents, id: \.self) { url in
                Button(url.lastPathComponent) { open([url]) }
            }
            Divider()
            Button("Clear Menu") { Access.shared.clearRecents() }
        }
    }

    private func open(_ urls: [URL]) {
        var urls = urls
        // Fill the empty welcome window before opening new ones.
        if let focusedRoot, focusedRoot.wrappedValue == nil, !urls.isEmpty {
            focusedRoot.wrappedValue = urls.removeFirst()
        }
        urls.forEach { openWindow(value: $0) }
    }
}

private struct HelpCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("mlisb Help") {
            if let url = Bundle.main.url(forResource: "mlisb Help", withExtension: "md") { openWindow(value: url) }
        }
        Button("Third-Party Notices") {
            if let url = Bundle.main.url(forResource: "Third-Party Notices", withExtension: "md") { openWindow(value: url) }
        }
        Button("mlisb on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/favoretti/mlisb")!) }
    }
}

extension FocusedValues {
    @Entry var workspaceRoot: Binding<URL?>?
}

@MainActor func chooseFilesOrFolders() -> [URL] {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.folder] + FolderSearch.extensions.compactMap { UTType(filenameExtension: $0) }
    return panel.runModal() == .OK ? panel.urls : []
}

/// A sandboxed app can't write to /usr/local/bin, so the user runs the command.
@MainActor func showInstallCommandLineTool() {
    let script = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''") + "/Contents/Resources/bin/mlisb"
    let command = "sudo mkdir -p /usr/local/bin && sudo ln -sf '\(script)' /usr/local/bin/mlisb"
    let alert = NSAlert()
    alert.messageText = "Install the mlisb command"
    alert.informativeText = "Run this once in Terminal. After that, “mlisb notes.md” or “mlisb .” opens files and folders in mlisb.\n\n\(command)"
    alert.addButton(withTitle: "Copy Command")
    alert.addButton(withTitle: "Close")
    if alert.runModal() == .alertFirstButtonReturn {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
