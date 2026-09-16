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
    var sortOrder = [KeyPathComparator(\FileItem.name, comparator: .localizedStandard)] {
        didSet { items.sort(using: sortOrder) }
    }

    init(_ url: URL) {
        history = History(url)
        reload()
    }

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
        selection = []
        reload()
    }

    func goBack() { history.goBack(); reload() }
    func goForward() { history.goForward(); reload() }
    func goUp() { if url.path != "/" { go(to: url.deletingLastPathComponent()) } }

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

@Observable @MainActor
final class Browser {
    private(set) var panes = [Pane(.homeDirectory)]
    var activeID: Pane.ID?

    var active: Pane { panes.first { $0.id == activeID } ?? panes[0] }
    var tab: Tab { active.selected }

    func toggleSplit() {
        if panes.count == 1 { panes.append(Pane(tab.url)) } else { panes.removeLast() }
    }
}
