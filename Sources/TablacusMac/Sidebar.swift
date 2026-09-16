import SwiftUI

@Observable @MainActor
final class Favorites {
    static let shared = Favorites()
    private static let key = "favorites"

    private let defaults: UserDefaults
    private(set) var urls: [URL]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        urls = defaults.stringArray(forKey: Self.key)?.map { URL(fileURLWithPath: $0) }
            ?? [.homeDirectory, .desktopDirectory, .documentsDirectory, .downloadsDirectory, URL(fileURLWithPath: "/Applications")]
    }

    func insert(_ dropped: [URL], at index: Int) {
        var index = min(index, urls.count)
        for url in dropped.map(\.standardizedFileURL) where FileItem(url).isFolder && !urls.contains(where: { $0.path == url.path }) {
            urls.insert(url, at: index)
            index += 1
        }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        urls.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0.path == url.path }
        save()
    }

    private func save() {
        defaults.set(urls.map(\.path), forKey: Self.key)
    }
}

struct SidebarView: View {
    let browser: Browser
    @State private var favorites = Favorites.shared
    @State private var selection: URL?

    var body: some View {
        List(selection: $selection) {
            Section("よく使う項目") {
                ForEach(favorites.urls, id: \.self) { url in
                    row(url).contextMenu {
                        Button("サイドバーから削除") { favorites.remove(url) }
                    }
                }
                .onMove { favorites.move(from: $0, to: $1) }
                .dropDestination(for: URL.self) { urls, index in favorites.insert(urls, at: index) }
            }
            Section("場所") {
                ForEach(FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: .skipHiddenVolumes) ?? [], id: \.self) { url in
                    row(url)
                }
            }
        }
        // 選択状態を残すと同じ項目をもう一度クリックしても移動しないため、移動したら選択を外す
        .onChange(of: selection) {
            guard let selection else { return }
            browser.tab.go(to: selection)
            self.selection = nil
        }
    }

    private func row(_ url: URL) -> some View {
        Label { Text(FileManager.default.displayName(atPath: url.path)) } icon: { FileIcon(url: url) }
            .tag(url)
    }
}
