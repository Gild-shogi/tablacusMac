import SwiftUI

struct BrowserView: View {
    @State private var browser = Browser()
    @FocusState private var focusedPane: Pane.ID?

    private var places: [URL] {
        let favorites: [URL] = [.homeDirectory, .desktopDirectory, .documentsDirectory, .downloadsDirectory, URL(fileURLWithPath: "/Applications")]
        return favorites + (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: .skipHiddenVolumes) ?? [])
    }

    var body: some View {
        NavigationSplitView {
            List(places, id: \.self) { url in
                Button { browser.tab.go(to: url) } label: {
                    Label { Text(FileManager.default.displayName(atPath: url.path)) } icon: { FileIcon(url: url) }
                }
                .buttonStyle(.plain)
            }
        } detail: {
            HSplitView {
                ForEach(browser.panes) { pane in
                    PaneView(pane: pane, focus: $focusedPane)
                        .overlay(alignment: .top) {
                            if browser.panes.count > 1, pane.id == browser.active.id {
                                Color.accentColor.frame(height: 2)
                            }
                        }
                }
            }
        }
        .navigationTitle(browser.tab.title)
        .focusedSceneValue(\.browser, browser)
        // サイドバーやメニューの操作先として、最後にフォーカスしたペインを覚えておく
        .onChange(of: focusedPane) { if let focusedPane { browser.activeID = focusedPane } }
    }
}

struct PaneView: View {
    let pane: Pane
    let focus: FocusState<Pane.ID?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(pane.tabs) { tab in
                            HStack(spacing: 6) {
                                Text(tab.title).lineLimit(1)
                                Button { pane.close(tab) } label: { Image(systemName: "xmark").font(.caption2) }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(tab.id == pane.selectedID ? Color.accentColor.opacity(0.25) : .clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                pane.selectedID = tab.id
                                focus.wrappedValue = pane.id
                            }
                        }
                    }
                }
                Button { pane.newTab() } label: { Image(systemName: "plus") }
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderless)
            .background(.bar)
            Divider()
            TabContent(pane: pane, tab: pane.selected, focus: focus)
                .id(pane.selectedID)
        }
    }
}

struct TabContent: View {
    let pane: Pane
    @Bindable var tab: Tab
    let focus: FocusState<Pane.ID?>.Binding
    @State private var path = ""
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { tab.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(tab.history.back.isEmpty)
                Button { tab.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(tab.history.forward.isEmpty)
                Button { tab.goUp() } label: { Image(systemName: "arrow.up") }
                    .disabled(tab.url.path == "/")
                TextField("パス", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(openTypedPath)
            }
            .buttonStyle(.borderless)
            .padding(6)

            if let error = tab.error {
                Text(error).foregroundStyle(.red).padding(6)
            }

            Table(of: FileItem.self, selection: $tab.selection, sortOrder: $tab.sortOrder) {
                TableColumn("名前", value: \.name, comparator: .localizedStandard) { item in
                    Label { Text(item.name) } icon: { FileIcon(url: item.url) }
                }
                TableColumn("更新日時", value: \.modified) { Text($0.modified, format: .dateTime) }
                TableColumn("種類", value: \.kind)
                TableColumn("サイズ", value: \.size) { item in
                    Text(item.isFolder ? "" : item.size.formatted(.byteCount(style: .file)))
                }
            } rows: {
                ForEach(tab.items) { item in
                    TableRow(item)
                        .draggable(item.url)
                        .dropDestination(for: URL.self) { urls in
                            FileOperations.drop(urls, into: item.isFolder ? item.url : tab.url)
                        }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                FileOperations.drop(urls, into: tab.url)
                return true
            }
            .contextMenu(forSelectionType: FileItem.ID.self) { ids in
                if ids.isEmpty {
                    Button("貼り付け") { FileOperations.paste(into: tab.url) }
                    Button("新規フォルダ") { tab.createFolder() }
                } else {
                    Button("開く") { tab.open(ids) }
                    Button("新しいタブで開く") { for folder in tab.folders(in: ids) { pane.newTab(folder) } }
                        .disabled(tab.folders(in: ids).isEmpty)
                    Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting(Array(ids)) }
                    Divider()
                    Button("名前を変更") { tab.renaming = ids.first }
                        .disabled(ids.count != 1)
                    Button("ゴミ箱に入れる") { FileOperations.trash(Array(ids)) }
                }
            } primaryAction: { tab.open($0) }
            .onCopyCommand { providers(cut: false) }
            .onCutCommand { providers(cut: true) }
            .onPasteCommand(of: [.fileURL]) { _ in FileOperations.paste(into: tab.url) }
            .onKeyPress(.return) { tab.open(tab.selection); return .handled }
            .onKeyPress(Self.f2) {
                guard tab.selection.count == 1 else { return .ignored }
                tab.renaming = tab.selection.first
                return .handled
            }
            // Tablacus（Explorer）に合わせ ⌫ は上の階層へ。⌘⌫ と ⌦ はゴミ箱
            .onKeyPress(keys: [.delete, .deleteForward]) { press in
                if press.key == .delete && !press.modifiers.contains(.command) {
                    tab.goUp()
                } else {
                    FileOperations.trash(Array(tab.selection))
                }
                return .handled
            }
            .focused(focus, equals: pane.id)
        }
        .onChange(of: tab.url, initial: true) { path = tab.url.path }
        .onChange(of: tab.renaming) { newName = tab.renaming?.lastPathComponent ?? "" }
        .alert("名前を変更", isPresented: Binding(get: { tab.renaming != nil }, set: { if !$0 { tab.renaming = nil } })) {
            TextField("名前", text: $newName)
            Button("変更") { if let url = tab.renaming { tab.rename(url, to: newName) } }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private static let f2 = KeyEquivalent(Character(UnicodeScalar(UInt32(NSF2FunctionKey))!))

    private func providers(cut: Bool) -> [NSItemProvider] {
        FileOperations.cutPaths = cut ? Set(tab.selection.map(\.path)) : []
        return tab.selection.map { NSItemProvider(object: $0 as NSURL) }
    }

    private func openTypedPath() {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            tab.go(to: URL(fileURLWithPath: expanded))
        } else {
            NSSound.beep()
            path = tab.url.path
        }
    }
}

struct FileIcon: View {
    let url: URL

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: 16, height: 16)
    }
}
