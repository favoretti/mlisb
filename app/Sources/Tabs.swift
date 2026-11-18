import AppKit
import SwiftUI

/// Where a window's tabs are shown.
enum TabLayout: String, CaseIterable, Identifiable {
    case top, left

    var id: Self { self }
    var label: String { self == .top ? "Across the top" : "Down the left side" }
}

/// The tabs of one window, for the strip down its left side. They are the system's own window tabs,
/// so switching, closing, merging and restoring keep working; only the bar they are drawn in changes.
@MainActor @Observable final class WindowTabs {
    struct Tab: Identifiable, Equatable {
        let id: ObjectIdentifier
        let title: String
        let isFolder: Bool
    }

    private(set) var tabs: [Tab] = []
    private(set) var selected: ObjectIdentifier?
    @ObservationIgnored weak var window: NSWindow?
    /// What each window shows, so a tab can say whether it is a folder.
    @ObservationIgnored fileprivate static let roots = NSMapTable<NSWindow, NSURL>.weakToStrongObjects()

    /// `tabbedWindows` and not `tabGroup`: reading `tabGroup` creates a group, and a window that already
    /// has one of its own is no longer added to another window's tabs.
    private var windows: [NSWindow] { window.map { $0.tabbedWindows ?? [$0] } ?? [] }

    func refresh() {
        let now = windows.map { window in
            Tab(id: ObjectIdentifier(window), title: window.title,
                isFolder: Self.roots.object(forKey: window).map { FS.isDir($0 as URL) } ?? false)
        }
        if now != tabs { tabs = now }
        let current = window.map { ObjectIdentifier($0.tabbedWindows == nil ? $0 : $0.tabGroup?.selectedWindow ?? $0) }
        if current != selected { selected = current }
    }

    private func window(_ id: ObjectIdentifier) -> NSWindow? { windows.first { ObjectIdentifier($0) == id } }

    func select(_ id: ObjectIdentifier) {
        guard let target = window(id) else { return }
        if let window, window.tabbedWindows != nil { window.tabGroup?.selectedWindow = target } else { target.makeKeyAndOrderFront(nil) }
    }

    func close(_ id: ObjectIdentifier) { window(id)?.performClose(nil) }

    func closeOthers(_ id: ObjectIdentifier) {
        for other in windows where ObjectIdentifier(other) != id { other.performClose(nil) }
    }

    func moveToNewWindow(_ id: ObjectIdentifier) { window(id)?.moveTabToNewWindow(nil) }
}

/// Connects a SwiftUI window to its NSWindow: applies the tab-or-window choice, hides the system's
/// tab bar when the tabs are drawn down the side, and keeps `tabs` current.
struct WindowLink: NSViewRepresentable {
    let openIn: OpenIn
    let layout: TabLayout
    let root: URL?
    let tabs: WindowTabs

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.openIn = openIn
        view.layout = layout
        view.root = root
        view.tabs = tabs
        view.apply()
    }

    final class Probe: NSView {
        var openIn = OpenIn.current
        var layout = TabLayout.top
        var root: URL?
        var tabs: WindowTabs?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            // Tabs come and go without a notification of their own; a window update follows every such change.
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.apply() } }
            apply()
        }

        func apply() {
            guard let window else { return }
            if window.tabbingMode != openIn.tabbingMode { window.tabbingMode = openIn.tabbingMode }
            WindowTabs.roots.setObject(root as NSURL?, forKey: window)
            tabs?.window = window
            tabs?.refresh()
            // The system's bar is a title bar accessory; hiding it is all that "down the left side" takes away.
            for accessory in window.titlebarAccessoryViewControllers where Self.isTabBar(accessory.view) {
                if accessory.isHidden != (layout == .left) { accessory.isHidden = layout == .left }
            }
        }

        private static func isTabBar(_ view: NSView) -> Bool {
            String(describing: type(of: view)).contains("TabBar") || view.subviews.contains(where: isTabBar)
        }
    }
}

/// The window's tabs as a list down its left side.
struct TabStrip: View {
    let tabs: WindowTabs
    @Environment(\.openWindow) private var openWindow
    @State private var hovered: ObjectIdentifier?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tabs.tabs) { tab in row(tab) }
                }
                .padding(6)
            }
            Divider()
            Menu {
                Button("New Document…") { if let url = createNewDocument() { openWindow(value: url) } }
                Button("Open…") { chooseFilesOrFolders().forEach { openWindow(value: $0) } }
            } label: {
                Label("New Tab", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .padding(8)
        }
        .frame(width: 190)
        .background(.bar)
    }

    private func row(_ tab: WindowTabs.Tab) -> some View {
        let isSelected = tab.id == tabs.selected
        return HStack(spacing: 6) {
            Image(systemName: tab.isFolder ? "folder" : "doc.text").foregroundStyle(.secondary)
            Text(tab.title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if hovered == tab.id {
                Button { tabs.close(tab.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Close Tab")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { tabs.select(tab.id) }
        .onHover { hovered = $0 ? tab.id : (hovered == tab.id ? nil : hovered) }
        .contextMenu {
            Button("Close Tab") { tabs.close(tab.id) }
            Button("Close Other Tabs") { tabs.closeOthers(tab.id) }.disabled(tabs.tabs.count < 2)
            Button("Move Tab to New Window") { tabs.moveToNewWindow(tab.id) }.disabled(tabs.tabs.count < 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
