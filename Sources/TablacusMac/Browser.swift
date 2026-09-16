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
    private(set) var error: String?
    var selection = Set<FileItem.ID>()
    var renaming: URL?
    // deinit から止めるため。DispatchSource 自体はスレッドセーフ
    @ObservationIgnored nonisolated(unsafe) private var watcher: DispatchSourceFileSystemObject?
    var sortOrder = [KeyPathComparator(\FileItem.name, comparator: .localizedStandard)] {
        didSet { items.sort(using: sortOrder) }
    }

    init(_ url: URL) {
        history = History(url)
        didNavigate()
    }

    deinit { watcher?.cancel() }

    var url: URL { history.current }
    var title: String { FileManager.default.displayName(atPath: url.path) }

    func reload() {
        do {
            // ponytail: メインスレッドで同期列挙。数万件のフォルダで固まるようなら Task.detached へ移す
            items = try FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: Array(FileItem.keys), options: .skipsHiddenFiles)
                .map(FileItem.init)
                .sorted(using: sortOrder)
            error = nil
        } catch {
            items = []
            self.error = error.localizedDescription
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
        selection = []
        reload()
        watcher?.cancel()
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { watcher = nil; return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        watcher = source
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

    func folders(in ids: Set<FileItem.ID>) -> [URL] {
        items.filter { ids.contains($0.id) && $0.isFolder }.map(\.url)
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

    init(_ url: URL) {
        let tab = Tab(url)
        tabs = [tab]
        selectedID = tab.id
    }

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

enum Layout: String, CaseIterable, Identifiable {
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
    private(set) var panes = [Pane(.homeDirectory)]
    private(set) var layout = Layout.single
    var activeID: Pane.ID?

    var visiblePanes: [Pane] { Array(panes.prefix(layout.paneCount)) }
    var active: Pane { visiblePanes.first { $0.id == activeID } ?? panes[0] }
    var tab: Tab { active.selected }

    func setLayout(_ layout: Layout) {
        while panes.count < layout.paneCount { panes.append(Pane(tab.url)) }
        self.layout = layout
    }
}
