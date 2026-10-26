import AppKit
import Observation

struct History: Equatable {
    private(set) var back: [URL] = []
    private(set) var current: URL
    private(set) var forward: [URL] = []

    init(_ url: URL) { current = url }

    mutating func visit(_ url: URL) {
        guard url != current else { return }
        back.append(current)
        current = url
        forward.removeAll()
    }

    mutating func goBack() {
        guard let url = back.popLast() else { return }
        forward.append(current)
        current = url
    }

    mutating func goForward() {
        guard let url = forward.popLast() else { return }
        back.append(current)
        current = url
    }
}

struct FileItem: Identifiable {
    static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey]

    let url: URL
    let name: String
    let isFolder: Bool
    let size: Int64
    let modified: Date
    let kind: String
    var id: URL { url }

    init(_ url: URL) {
        // シンボリックリンク（/tmp 等）はリンク先の種別で扱う
        let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: Self.keys)
        self.url = url
        name = url.lastPathComponent
        isFolder = values?.isDirectory == true && values?.isPackage != true
        size = isFolder ? -1 : Int64(values?.fileSize ?? 0)
        modified = values?.contentModificationDate ?? .distantPast
        kind = values?.localizedTypeDescription ?? ""
    }
}

@Observable @MainActor
final class Tab: Identifiable {
    let id = UUID()
    private(set) var history: History
    private(set) var items: [FileItem] = []
    /// Finder のリスト表示と同じく、一覧の中で開いて中身を見せているフォルダ
    private(set) var expanded = Set<URL>()
    private(set) var children: [URL: [FileItem]] = [:]
    private(set) var error: String?
    var selection = Set<FileItem.ID>()
    var renaming: URL?
    var wantsFilterFocus = false
    var filter = "" {
        // 見えない項目を選択したままゴミ箱などの操作をしないよう、絞り込みで隠れたら選択から外す
        didSet { selection.formIntersection(visibleItems.map(\.id)) }
    }
    // deinit から止めるため。DispatchSource 自体はスレッドセーフ
    @ObservationIgnored nonisolated(unsafe) private var watchers: [URL: DispatchSourceFileSystemObject] = [:]
    var sortOrder = [KeyPathComparator(\FileItem.name, comparator: .localizedStandard)] {
        didSet {
            items.sort(using: sortOrder)
            for url in children.keys { children[url]?.sort(using: sortOrder) }
        }
    }

    init(_ url: URL) {
        history = History(url)
        didNavigate()
    }

    deinit { watchers.values.forEach { $0.cancel() } }

    var url: URL { history.current }
    var title: String { FileManager.default.displayName(atPath: url.path) }

    var visibleItems: [FileItem] {
        let terms = filter.split(whereSeparator: \.isWhitespace)
        return terms.isEmpty ? items : items.filter { item in terms.allSatisfy { item.name.localizedStandardContains($0) } }
    }

    func reload() {
        do {
            items = try contents(of: url)
            error = nil
        } catch {
            items = []
            self.error = error.localizedDescription
        }
        // 消えた・読めなくなったフォルダは閉じる
        children = expanded.reduce(into: [:]) { $0[$1] = try? contents(of: $1) }
        expanded = Set(children.keys)
        watch()
    }

    // ponytail: メインスレッドで同期列挙。数万件のフォルダで固まるようなら Task.detached へ移す
    private func contents(of folder: URL) throws -> [FileItem] {
        try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(FileItem.keys))
            .map(FileItem.init)
            .sorted(using: sortOrder)
    }

    func setExpanded(_ folder: URL, _ isExpanded: Bool) {
        if isExpanded {
            expanded.insert(folder)
        } else {
            // 中で開いていたフォルダも閉じ、隠れた項目が選択に残らないようにする
            expanded = expanded.filter { $0 != folder && !$0.path.hasPrefix(folder.path + "/") }
            selection = selection.filter { !$0.path.hasPrefix(folder.path + "/") }
        }
        reload()
    }

    /// 表示中のフォルダと開いているフォルダの変更を監視し、一覧を読み直す
    private func watch() {
        let folders = expanded.union([url])
        for (folder, source) in watchers where !folders.contains(folder) {
            source.cancel()
            watchers[folder] = nil
        }
        for folder in folders where watchers[folder] == nil {
            let descriptor = Darwin.open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reload() } }
            source.setCancelHandler { Darwin.close(descriptor) }
            source.resume()
            watchers[folder] = source
        }
    }

    func go(to url: URL) {
        history.visit(url.standardizedFileURL)
        didNavigate()
    }

    func goBack() { history.goBack(); didNavigate() }
    func goForward() { history.goForward(); didNavigate() }
    func goUp() { if url.path != "/" { go(to: url.deletingLastPathComponent()) } }

    private func didNavigate() {
        filter = ""
        selection = []
        expanded = []
        reload()
    }

    func createFolder() {
        let folder = uniqueURL(for: "名称未設定フォルダ", in: url)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            reload()
            selection = Set(items.filter { $0.url.path == folder.path }.map(\.id))
            renaming = folder
        } catch {
            FileOperations.showError(error.localizedDescription)
        }
    }

    func rename(_ source: URL, to name: String) {
        guard name != source.lastPathComponent else { return }
        guard !name.isEmpty, !name.contains("/") else {
            FileOperations.showError("「\(name)」は名前に使えません")
            return
        }
        // moveItem は移動先が既にあればエラーになるので上書きは起きない
        do {
            try FileManager.default.moveItem(at: source, to: source.deletingLastPathComponent().appendingPathComponent(name))
        } catch {
            FileOperations.showError(error.localizedDescription)
        }
    }

    /// 複数選択やファイル混じりのときは貼り付け先を決められないので nil
    var selectedFolder: URL? { selection.count == 1 ? folders(in: selection).first : nil }

    func folders(in ids: Set<FileItem.ID>) -> [URL] {
        (items + children.values.joined()).filter { ids.contains($0.id) && $0.isFolder }.map(\.url)
    }

    func open(_ ids: Set<FileItem.ID>) {
        let folders = folders(in: ids)
        if ids.count == 1, let folder = folders.first {
            go(to: folder)
        } else {
            ids.forEach { NSWorkspace.shared.open($0) }
        }
    }
}

@Observable @MainActor
final class Pane: Identifiable {
    let id = UUID()
    private(set) var tabs: [Tab]
    var selectedID: Tab.ID

    init(urls: [URL], selected: Int) {
        let tabs = (urls.isEmpty ? [.homeDirectory] : urls).map(Tab.init)
        self.tabs = tabs
        selectedID = tabs[min(max(selected, 0), tabs.count - 1)].id
    }

    convenience init(_ url: URL) { self.init(urls: [url], selected: 0) }

    var selected: Tab { tabs.first { $0.id == selectedID } ?? tabs[0] }

    func newTab(_ url: URL? = nil) {
        let tab = Tab(url ?? selected.url)
        tabs.append(tab)
        selectedID = tab.id
    }

    func close(_ tab: Tab) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        if selectedID == tab.id { selectedID = tabs[min(index, tabs.count - 1)].id }
    }
}

enum Layout: String, CaseIterable, Identifiable, Codable {
    case single = "1画面"
    case columns = "左右2画面"
    case rows = "上下2画面"
    case threeColumns = "3列"
    case grid = "2×2"

    var id: Self { self }

    var paneCount: Int {
        switch self {
        case .single: 1
        case .columns, .rows: 2
        case .threeColumns: 3
        case .grid: 4
        }
    }
}

@Observable @MainActor
final class Browser {
    // 画面数を減らしてもペインは破棄せず隠すだけにし、戻したときにタブを復元する
    private(set) var panes: [Pane]
    private(set) var layout = Layout.single
    var activeID: Pane.ID?

    init(restoring state: BrowserState? = nil) {
        let panes = state?.panes.map { Pane(urls: $0.tabs.map { URL(fileURLWithPath: $0) }, selected: $0.selected) } ?? []
        self.panes = panes.isEmpty ? [Pane(.homeDirectory)] : panes
        setLayout(state?.layout ?? .single)
        if let active = state?.active, self.panes.indices.contains(active) { activeID = self.panes[active].id }
    }

    var state: BrowserState {
        BrowserState(
            layout: layout,
            panes: panes.map { pane in
                BrowserState.PaneState(tabs: pane.tabs.map(\.url.path), selected: pane.tabs.firstIndex { $0.id == pane.selectedID } ?? 0)
            },
            active: panes.firstIndex { $0.id == active.id } ?? 0
        )
    }

    var visiblePanes: [Pane] { Array(panes.prefix(layout.paneCount)) }
    var active: Pane { visiblePanes.first { $0.id == activeID } ?? panes[0] }
    var tab: Tab { active.selected }

    func setLayout(_ layout: Layout) {
        while panes.count < layout.paneCount { panes.append(Pane(tab.url)) }
        self.layout = layout
    }
}

struct BrowserState: Codable, Equatable {
    struct PaneState: Codable, Equatable {
        var tabs: [String]
        var selected: Int
    }

    private static let key = "browserState"
    @MainActor private static var isRestored = false

    var layout: Layout
    var panes: [PaneState]
    var active: Int

    /// ponytail: 保存する状態は1つだけ。最初のウィンドウだけ復元し、⌘N の新規ウィンドウはホームから始める
    @MainActor static func restoreOnce() -> BrowserState? {
        guard !isRestored else { return nil }
        isRestored = true
        return UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
