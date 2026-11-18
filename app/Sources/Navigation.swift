import SwiftUI

/// Per-window state that the menu commands reach through a focused scene value.
@MainActor @Observable final class NavState {
    var quickOpen = false
    /// Bumped by "Find in Folder…"; the sidebar's search field focuses itself on change.
    var searchRequest = 0
    var hasFolder = false
}

extension FocusedValues {
    @Entry var nav: NavState?
}

struct NavigationCommands: Commands {
    @FocusedValue(\.nav) private var nav
    @FocusedValue(\.editorBus) private var bus
    @AppStorage("showOutline") private var showOutline = false
    @AppStorage("inspectorTab") private var tab = InspectorTab.contents

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find in Folder…") { nav?.searchRequest += 1 }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(nav?.hasFolder != true)
        }
        CommandGroup(after: .newItem) {
            Button("Open Quickly…") { nav?.quickOpen = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(nav == nil)
        }
        CommandGroup(before: .sidebar) {
            Button("Problems") { tab = .problems; showOutline = true }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(bus == nil)
        }
    }
}
