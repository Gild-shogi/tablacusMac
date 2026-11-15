import AppKit
import UniformTypeIdentifiers

/// ドラッグ&ドロップの不具合を追うための記録。~/Library/Logs/TablacusMac.log
func debugLog(_ message: String) {
    let line = "\(Date().formatted(.iso8601)) \(message)\n"
    let url = URL.homeDirectory.appending(path: "Library/Logs/TablacusMac.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

enum FileOperation: Sendable {
    case copy, move
}

struct FileOperationError: LocalizedError {
    let errorDescription: String?
}

/// 同名の項目があれば「名前-1.拡張子」「名前-2.拡張子」…の形で空いている名前を返す
func uniqueURL(for name: String, in folder: URL) -> URL {
    let original = folder.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: original.path) else { return original }

    let ext = (name as NSString).pathExtension
    func candidate(_ base: String) -> URL {
        folder.appendingPathComponent(ext.isEmpty ? base : "\(base).\(ext)")
    }
    var base = (name as NSString).deletingPathExtension
    var number = 1
    // 「a-1.txt」の複製は「a-2.txt」にする。元の「a.txt」が無ければ「report-2024」のような名前の一部とみなす
    if let dash = base.lastIndex(of: "-"), let copyNumber = Int(base[base.index(after: dash)...]),
       FileManager.default.fileExists(atPath: candidate(String(base[..<dash])).path) {
        base = String(base[..<dash])
        number = copyNumber + 1
    }
    while FileManager.default.fileExists(atPath: candidate("\(base)-\(number)").path) {
        number += 1
    }
    return candidate("\(base)-\(number)")
}

/// 既存の項目は上書きせず、同名があれば別名で残す
func transfer(_ sources: [URL], to folder: URL, _ operation: FileOperation) throws {
    let folderPath = folder.standardizedFileURL.path
    for source in sources.map(\.standardizedFileURL) {
        guard source.isFileURL, source.path.hasPrefix("/") else {
            throw FileOperationError(errorDescription: "「\(source.absoluteString)」はファイルのパスとして扱えません")
        }
        if source.path == folderPath { continue }
        if operation == .move && source.deletingLastPathComponent().path == folderPath { continue }
        if folderPath.hasPrefix(source.path + "/") {
            throw FileOperationError(errorDescription: "「\(source.lastPathComponent)」を自分自身の中にはコピー・移動できません")
        }
        let destination = uniqueURL(for: source.lastPathComponent, in: folder)
        switch operation {
        case .copy: try FileManager.default.copyItem(at: source, to: destination)
        case .move: try FileManager.default.moveItem(at: source, to: destination)
        }
    }
}

/// 選択中のフォルダの中へ貼り付ける。ただし貼り付ける項目自身が選ばれていれば複製とみなし表示中のフォルダへ
func pasteDestination(for sources: [URL], current: URL, selectedFolder: URL?) -> URL {
    guard let selectedFolder, !sources.contains(where: { $0.standardizedFileURL.path == selectedFolder.standardizedFileURL.path }) else {
        return current
    }
    return selectedFolder
}

func isSameVolume(_ a: URL, _ b: URL) -> Bool {
    let ids = [a, b].map { (try? $0.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject }
    return ids[0] != nil && ids[0] == ids[1]
}

@MainActor
enum FileOperations {
    /// ⌘X した項目。貼り付け時にクリップボードの中身と一致すれば移動として扱う
    static var cutPaths: Set<String> = []

    static func perform(_ sources: [URL], to folder: URL, _ operation: FileOperation) {
        // ponytail: 進捗表示なし。大きなコピーで完了が分かりにくいなら進捗バーを足す
        Task.detached {
            do {
                try transfer(sources, to: folder, operation)
            } catch {
                let message = error.localizedDescription
                debugLog("transfer failed: \(message)")
                await showError(message)
            }
        }
    }

    /// SwiftUI がドラッグ用に書き出す URL はこの環境では中身が空になるため、開始時のファイルを覚えておいて使う
    static var draggingURLs: [URL] = []

    static func beginDrag(_ urls: [URL], representing url: URL) -> NSItemProvider {
        draggingURLs = urls
        debugLog("drag start \(urls.map(\.lastPathComponent))")
        return fileProvider(for: url)
    }

    /// SwiftUI・ドラッグ用ペーストボード・アプリ内の記録の順に、パスとして使えるものを採る
    static func resolveDropped(_ candidates: [[URL]]) -> [URL] {
        for list in candidates {
            let valid = list.filter { $0.isFileURL && $0.path.hasPrefix("/") }
            if !valid.isEmpty { return valid }
        }
        return []
    }

    /// 遅延のデータ表現だと他のアプリへは中身が届かないため、NSURL を渡して AppKit に Finder と同じ形で書かせる
    static func fileProvider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = url.lastPathComponent
        return provider
    }

    /// ドロップ中だけ有効。ドラッグ中のファイルはここにも載るので、取り出せなかったときの確認に使う
    static func draggedURLs() -> [URL] {
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    static func drop(_ providers: [NSItemProvider], into folder: URL, from source: String) {
        let dragged = draggedURLs()
        debugLog("drop from \(source) into \(folder.path) types=\(providers.map(\.registeredTypeIdentifiers)) dragged=\(dragged.map(\.path))")
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let loaded: (Data?, String?) = await withCheckedContinuation { continuation in
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                        continuation.resume(returning: (data, error?.localizedDescription))
                    }
                }
                if let data = loaded.0, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else {
                    debugLog("provider load failed bytes=\(loaded.0?.count ?? -1) error=\(loaded.1 ?? "なし")")
                }
            }
            let resolved = resolveDropped([urls, dragged, draggingURLs])
            debugLog("drop resolved urls=\(resolved.map(\.path))")
            drop(resolved, into: folder)
        }
    }

    static func drop(_ sources: [URL], into folder: URL) {
        draggingURLs = []
        guard !sources.isEmpty else { return }
        let copies = NSEvent.modifierFlags.contains(.option) || !sources.allSatisfy { isSameVolume($0, folder) }
        debugLog("drop \(copies ? "copy" : "move") \(sources.map(\.lastPathComponent)) -> \(folder.path)")
        perform(sources, to: folder, copies ? .copy : .move)
    }

    static func copy(_ urls: [URL], cut: Bool) {
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
        cutPaths = cut ? Set(urls.map(\.path)) : []
    }

    /// move は Finder の ⌥⌘V。⌘C した項目でも移動する
    static func paste(into current: URL, selectedFolder: URL?, move: Bool = false) {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        let isCut = move || Set(urls.map(\.path)) == cutPaths
        if isCut { cutPaths = [] }
        perform(urls, to: pasteDestination(for: urls, current: current, selectedFolder: selectedFolder), isCut ? .move : .copy)
    }

    static func copyPaths(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).sorted().joined(separator: "\n"), forType: .string)
    }

    /// 開いたフォルダの中の項目も選べるため、それぞれ元のフォルダに複製する
    static func duplicate(_ urls: [URL]) {
        for (folder, sources) in Dictionary(grouping: urls, by: { $0.deletingLastPathComponent() }) {
            perform(sources, to: folder, .copy)
        }
    }

    /// ponytail: 1項目だけ。複数をまとめた「アーカイブ.zip」が要るなら一時フォルダに集めてから ditto する
    static func compress(_ url: URL) {
        let archive = uniqueURL(for: url.lastPathComponent + ".zip", in: url.deletingLastPathComponent())
        run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, archive.path], failure: "圧縮できませんでした")
    }

    static func showInfo(_ urls: [URL]) {
        runFinder("""
            tell application "Finder"
                activate
                repeat with p in argv
                    open information window of ((POSIX file (contents of p)) as alias)
                end repeat
            end tell
            """, urls, failure: "情報を表示できませんでした")
    }

    static func makeAlias(_ urls: [URL]) {
        runFinder("""
            tell application "Finder"
                repeat with p in argv
                    set original to (POSIX file (contents of p)) as alias
                    make new alias file at (container of original) to original
                end repeat
            end tell
            """, urls, failure: "エイリアスを作成できませんでした")
    }

    /// NSWorkspace.recycle は複数件を一度に捨てると先頭の1件しか「戻す」が効かないため Finder に任せる
    static func trash(_ urls: [URL]) {
        runFinder("""
            set targets to {}
            repeat with p in argv
                set end of targets to (POSIX file (contents of p)) as alias
            end repeat
            tell application "Finder" to delete targets
            """, urls, failure: "ゴミ箱に移動できませんでした")
    }

    /// script の中では argv で各項目のパスを受け取る
    private static func runFinder(_ script: String, _ urls: [URL], failure: String) {
        guard !urls.isEmpty else { return }
        run("/usr/bin/osascript", ["-e", "on run argv\n\(script)\nend run"] + urls.map(\.path), failure: failure)
    }

    private static func run(_ executable: String, _ arguments: [String], failure: String) {
        Task.detached {
            let process = Process()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderr
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    await showError("\(failure)\n\(message)")
                }
            } catch {
                let message = error.localizedDescription
                await showError(message)
            }
        }
    }

    static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
