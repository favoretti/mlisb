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
        let url: URL?
    }

    private(set) var tabs: [Tab] = []
    private(set) var selected: ObjectIdentifier?
    /// Whether this window is on screen. A tab in the background is a window that is not.
    private(set) var isShown = false
    @ObservationIgnored weak var window: NSWindow?
    /// The windows that show a folder, so a tab can say so without asking the disk on every update.
    @ObservationIgnored fileprivate static let folders = NSHashTable<NSWindow>.weakObjects()
    /// The file or folder each window shows, for a tab's Reveal in Finder.
    @ObservationIgnored fileprivate static let roots = NSMapTable<NSWindow, NSURL>.weakToStrongObjects()

    /// `tabbedWindows` and not `tabGroup`: reading `tabGroup` creates a group, and a window that already
    /// has one of its own is no longer added to another window's tabs.
    private var windows: [NSWindow] { window.map { $0.tabbedWindows ?? [$0] } ?? [] }

    func refresh() {
        let now = windows.map { window in
            Tab(id: ObjectIdentifier(window), title: window.tab.title,
                isFolder: Self.folders.contains(window), url: Self.roots.object(forKey: window) as URL?)
        }
        if now != tabs { tabs = now }
        let current = window.map { ObjectIdentifier($0.tabbedWindows == nil ? $0 : $0.tabGroup?.selectedWindow ?? $0) }
        if current != selected { selected = current }
        let shown = window?.isVisible ?? false
        if shown != isShown { isShown = shown }
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
    /// Last time's windows are still being reopened: a window without its file has no name yet.
    let reopening: Bool
    let tabs: WindowTabs

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.openIn = openIn
        view.layout = layout
        view.root = root
        view.reopening = reopening
        view.tabs = tabs
        view.apply()
    }

    final class Probe: NSView {
        var openIn = OpenIn.current
        var layout = TabLayout.top
        var root: URL? { didSet { if root != oldValue { isFolder = root.map(FS.isDir) ?? false } } }
        private var isFolder = false
        var reopening = false
        var tabs: WindowTabs?
        private var observers: [NSObjectProtocol] = []
        private var accessories: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // Tabs come and go without a notification of their own; a window update follows every such change.
            // Selecting a tab shows its window, which is reported as an occlusion change.
            observers = [NSWindow.didUpdateNotification, NSWindow.didChangeOcclusionStateNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                }
            }
            // The system's tab bar is added while windows are restored, long before the next update.
            accessories = window.observe(\.titlebarAccessoryViewControllers) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.hideTabBar() }
            }
            apply()
        }

        func apply() {
            guard let window else { return }
            if window.tabbingMode != openIn.tabbingMode { window.tabbingMode = openIn.tabbingMode }
            if isFolder { WindowTabs.folders.add(window) } else { WindowTabs.folders.remove(window) }
            if let root { WindowTabs.roots.setObject(root as NSURL, forKey: window) } else { WindowTabs.roots.removeObject(forKey: window) }
            // The title is the full path; a tab names only the file or folder.
            let name = root?.lastPathComponent ?? (reopening ? "" : "mlisb")
            if window.tab.title != name { window.tab.title = name }
            tabs?.window = window
            tabs?.refresh()
            hideTabBar()
        }

        /// The system's bar is a title bar accessory; hiding it is all that "down the left side" takes away.
        private func hideTabBar() {
            guard let window else { return }
            // While windows are restored the bar arrives as an empty accessory and is filled in later.
            let tabbed = window.tabbedWindows != nil
            for accessory in window.titlebarAccessoryViewControllers
            where Self.isTabBar(accessory.view) || (tabbed && accessory.view.subviews.isEmpty) {
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
    /// Every window has its own strip; one shared width keeps switching tabs from jumping.
    @AppStorage("tabStripWidth") private var width = TabStrip.defaultWidth
    @State private var dragStart: Double?

    static let defaultWidth = 190.0
    static let widths = 140.0...480.0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                // A window in the background draws no rows: every title change would lay them out again.
                // Nor does any window while the tabs are still being reopened and have no names.
                if tabs.isShown && !Reopening.shared.isActive {
                    VStack(spacing: 2) {
                        ForEach(tabs.tabs) { tab in row(tab) }
                    }
                    .padding(6)
                }
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
        .frame(width: Self.widths.clamp(width))
        .background(.bar)
        .overlay(alignment: .trailing) { resizeHandle }
    }

    private var resizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart ?? Self.widths.clamp(width)
                    dragStart = start
                    width = Self.widths.clamp(start + drag.translation.width)
                }
                .onEnded { _ in dragStart = nil })
            .onTapGesture(count: 2) { width = Self.defaultWidth }
            .help("Drag to resize; double-click for the default width")
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
            if let url = tab.url {
                Divider()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.standardizedFileURL.path, forType: .string)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
