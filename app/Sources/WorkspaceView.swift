import SwiftUI

struct WorkspaceView: View {
    @Binding var root: URL?
    @State private var document: Document?
    @State private var folder: FolderModel?
    @State private var nav = NavState()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let folder {
                FolderView(model: folder, nav: nav).id(folder.root)
            } else if let document {
                EditorPane(document: document)
            } else {
                ContentUnavailableView {
                    Label("mlisb", systemImage: "doc.richtext")
                } description: {
                    Text("Open a Markdown file or a folder.")
                } actions: {
                    Button("Open…") { root = chooseFilesOrFolders().first }
                }
            }
        }
        .navigationTitle(root?.lastPathComponent ?? "mlisb")
        // Files opened from Finder or the CLI go to the window already showing them
        // (or their folder); an empty window takes anything.
        .handlesExternalEvents(
            preferring: root.map { [$0.absoluteString] } ?? [],
            allowing: root.map { [$0.absoluteString] } ?? ["*"])
        .onOpenURL(perform: open)
        .focusedSceneValue(\.workspaceRoot, $root)
        .focusedSceneValue(\.nav, nav)
        .overlay(alignment: .top) {
            if nav.quickOpen {
                let open = folder?.document ?? document
                QuickOpenView(
                    nav: nav, root: folder?.root, headings: open.map { Outline.headings(in: $0.text) } ?? [],
                    openFile: { _ = folder?.show($0) },
                    goTo: { range in if let open { LineRequests.shared.pending = LineRequest(file: open.url, range: range) } })
            }
        }
        .onChange(of: root, initial: true) { _, root in
            document = nil
            folder = nil
            nav.hasFolder = false
            guard let root else { return }
            Access.shared.begin(root)
            if FS.isDir(root) { folder = FolderModel(root: root); nav.hasFolder = true } else { document = Document(url: root) }
            showRequestedFile()
        }
        .onChange(of: LineRequests.shared.pending) { showRequestedFile() }
    }

    /// A folder window selects the file a line request names; the editor then takes the request.
    private func showRequestedFile() {
        if let file = LineRequests.shared.pending?.file { _ = folder?.show(file) }
    }

    private func open(_ url: URL) {
        guard let root else { return self.root = url }
        if url.standardizedFileURL == root.standardizedFileURL { return }
        if let folder, FS.under(url, root) {
            if !folder.show(url) { folder.selection = url }
        } else {
            openWindow(value: url)
        }
    }
}

private struct FolderView: View {
    @Bindable var model: FolderModel
    let nav: NavState
    @State private var search: SearchModel
    @State private var visibility = NavigationSplitViewVisibility.automatic

    init(model: FolderModel, nav: NavState) {
        self.model = model
        self.nav = nav
        _search = State(initialValue: SearchModel(root: model.root))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            Group {
                if search.query.isEmpty {
                    List(selection: $model.selection) {
                        ForEach(model.children[model.root] ?? [], id: \.url) { RowView(entry: $0, model: model) }
                    }
                    .dropDestination(for: URL.self) { urls, _ in model.move(urls, into: model.root); return true }
                    .contextMenu(forSelectionType: URL.self) { menu($0.first) }
                } else {
                    SearchResultsView(search: search) { url, range in
                        if model.show(url) { LineRequests.shared.pending = LineRequest(file: url, range: range) }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { SidebarSearchField(search: search, nav: nav) }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240)
            .onChange(of: nav.searchRequest) { visibility = .all }
        } detail: {
            if let document = model.document {
                EditorPane(document: document, showInWorkspace: model.show).id(document.url)
            } else if let url = model.preview {
                Preview(url: url).id(url)
            } else {
                ContentUnavailableView("Select a file", systemImage: "doc")
            }
        }
        .alert("Error", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
        } message: {
            Text(model.error ?? "")
        }
    }

    @ViewBuilder private func menu(_ item: URL?) -> some View {
        let dir = item.map { FS.isDir($0) ? $0 : $0.deletingLastPathComponent() } ?? model.root
        Button("New File") { model.create(in: dir, folder: false) }
        Button("New Folder") { model.create(in: dir, folder: true) }
        if let item {
            Button("Rename") { model.renaming = item }
            Button("Move to Trash") { model.trash(item) }
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item ?? model.root]) }
    }
}

private struct RowView: View {
    let entry: Entry
    let model: FolderModel

    var body: some View {
        let dir = entry.isDir ? entry.url : entry.url.deletingLastPathComponent()
        let label = RowLabel(entry: entry, model: model)
            .draggable(entry.url)
            .dropDestination(for: URL.self) { urls, _ in model.move(urls, into: dir); return true }
        if entry.isDir {
            DisclosureGroup(isExpanded: Binding(
                get: { model.isExpanded(entry.url) }, set: { model.setExpanded(entry.url, $0) })
            ) {
                ForEach(model.children[entry.url] ?? [], id: \.url) { RowView(entry: $0, model: model) }
            } label: { label }
            .tag(entry.url)
        } else {
            label.tag(entry.url)
        }
    }
}

private struct RowLabel: View {
    let entry: Entry
    let model: FolderModel
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        if model.renaming == entry.url {
            TextField("Name", text: $name)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { model.renaming = nil }
                .onChange(of: focused) { _, focused in if !focused { commit() } }
                .onAppear { name = entry.url.lastPathComponent; focused = true }
        } else {
            Label(entry.url.lastPathComponent, systemImage: entry.isDir ? "folder" : FS.markdown.contains(entry.url.pathExtension.lowercased()) ? "doc.text" : "photo")
        }
    }

    private func commit() {
        guard model.renaming == entry.url else { return }
        model.renaming = nil
        model.rename(entry.url, to: name)
    }
}
