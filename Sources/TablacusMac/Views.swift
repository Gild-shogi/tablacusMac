import SwiftUI

struct BrowserView: View {
    // @State の初期値は View の再生成のたびに評価されるため、ディレクトリ読み込みを伴う Browser は表示時に一度だけ作る
    @State private var browser: Browser?

    var body: some View {
        if let browser {
            BrowserContent(browser: browser)
                .onChange(of: browser.state) { _, state in state.save() }
        } else {
            Color.clear.onAppear { browser = Browser(restoring: .restoreOnce()) }
        }
    }
}

struct BrowserContent: View {
    let browser: Browser
    @FocusState private var focusedPane: Pane.ID?

    private func paneView(_ pane: Pane) -> some View {
        PaneView(pane: pane, focus: $focusedPane)
            .overlay(alignment: .top) {
                if browser.layout != .single, pane.id == browser.active.id {
                    Color.accentColor.frame(height: 2)
                }
            }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(browser: browser)
        } detail: {
            let panes = browser.visiblePanes
            switch browser.layout {
            case .single:
                paneView(panes[0])
            case .columns, .threeColumns:
                HSplitView { ForEach(panes) { paneView($0) } }
            case .rows:
                VSplitView { ForEach(panes) { paneView($0) } }
            case .grid:
                VSplitView {
                    HSplitView { paneView(panes[0]); paneView(panes[1]) }
                    HSplitView { paneView(panes[2]); paneView(panes[3]) }
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
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            navigationBar

            if let error = tab.error {
                Text(error).foregroundStyle(.red).padding(6)
            }

            fileTable
        }
        .onChange(of: tab.url, initial: true) { path = tab.url.path }
        .onChange(of: tab.wantsFilterFocus) {
            guard tab.wantsFilterFocus else { return }
            isFilterFocused = true
            tab.wantsFilterFocus = false
        }
        .onChange(of: tab.renaming) { newName = tab.renaming?.lastPathComponent ?? "" }
        .alert("名前を変更", isPresented: Binding(get: { tab.renaming != nil }, set: { if !$0 { tab.renaming = nil } })) {
            TextField("名前", text: $newName)
            Button("変更") { if let url = tab.renaming { tab.rename(url, to: newName) } }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            ControlGroup {
                Button { tab.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(tab.history.back.isEmpty)
                Button { tab.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(tab.history.forward.isEmpty)
            }
            .fixedSize()
            Button { tab.goUp() } label: { Image(systemName: "arrow.up") }
                .disabled(tab.url.path == "/")
            TextField("パス", text: $path)
                .textFieldStyle(.roundedBorder)
                .onSubmit(openTypedPath)
            TextField("絞り込み（⌘F）", text: $tab.filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($isFilterFocused)
                .onSubmit { focus.wrappedValue = pane.id }
                .onExitCommand {
                    tab.filter = ""
                    focus.wrappedValue = pane.id
                }
        }
        .controlSize(.large)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var fileTable: some View {
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
            ForEach(tab.visibleItems) { item in
                TableRow(item)
                    .itemProvider {
                        // 選択中の項目をドラッグしたときは選択分をまとめて運ぶ
                        let urls = tab.selection.contains(item.id) ? Array(tab.selection) : [item.url]
                        return FileOperations.beginDrag(urls, representing: item.url)
                    }
                    .dropDestination(for: URL.self) { urls in
                        let dropped = FileOperations.resolveDropped([urls, FileOperations.draggedURLs(), FileOperations.draggingURLs])
                        debugLog("row drop onto \(item.name) swiftui=\(urls.map(\.path)) resolved=\(dropped.map(\.path))")
                        FileOperations.drop(dropped, into: item.isFolder ? item.url : tab.url)
                    }
            }
            // 行より下の空欄や行間へのドロップは、表の「行の挿入」として届く
            .dropDestination(for: URL.self) { index, urls in
                let dropped = FileOperations.resolveDropped([urls, FileOperations.draggedURLs(), FileOperations.draggingURLs])
                debugLog("list drop index=\(index) swiftui=\(urls.map(\.path)) resolved=\(dropped.map(\.path))")
                FileOperations.drop(dropped, into: tab.url)
            }
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            if ids.isEmpty {
                Button("貼り付け") { FileOperations.paste(into: tab.url, selectedFolder: nil) }
                Button("新規フォルダ") { tab.createFolder() }
                Divider()
                Button("パスをコピー") { copyPaths([tab.url]) }
                Button("WezTermで開く") { WezTerm.open(tab.url) }
            } else {
                Button("開く") { tab.open(ids) }
                Button("新しいタブで開く") { for folder in tab.folders(in: ids) { pane.newTab(folder) } }
                    .disabled(tab.folders(in: ids).isEmpty)
                Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting(Array(ids)) }
                Divider()
                Button("パスをコピー") { copyPaths(Array(ids)) }
                Button("WezTermで開く") { WezTerm.open(ids.count == 1 ? tab.folders(in: ids).first ?? tab.url : tab.url) }
                Divider()
                Button("名前を変更") { tab.renaming = ids.first }
                    .disabled(ids.count != 1)
                Button("ゴミ箱に入れる") { FileOperations.trash(Array(ids)) }
            }
        } primaryAction: { tab.open($0) }
        // Finder と同じく Return は名前変更、⌘↓ で開く
        .onKeyPress(keys: [.return, Self.f2]) { _ in
            guard tab.selection.count == 1 else { return .ignored }
            tab.renaming = tab.selection.first
            return .handled
        }
        .onKeyPress(keys: [.downArrow]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            tab.open(tab.selection)
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard !tab.selection.isEmpty else { return .ignored }
            FileOperations.trash(Array(tab.selection))
            return .handled
        }
        .focused(focus, equals: pane.id)
    }

    private static let f2 = KeyEquivalent(Character(UnicodeScalar(UInt32(NSF2FunctionKey))!))

    private func copyPaths(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).sorted().joined(separator: "\n"), forType: .string)
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
