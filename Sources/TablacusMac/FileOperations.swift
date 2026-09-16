import AppKit

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
                await showError(message)
            }
        }
    }

    static func drop(_ sources: [URL], into folder: URL) {
        let copies = NSEvent.modifierFlags.contains(.option) || !sources.allSatisfy { isSameVolume($0, folder) }
        perform(sources, to: folder, copies ? .copy : .move)
    }

    static func paste(into current: URL, selectedFolder: URL?) {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        let isCut = Set(urls.map(\.path)) == cutPaths
        if isCut { cutPaths = [] }
        perform(urls, to: pasteDestination(for: urls, current: current, selectedFolder: selectedFolder), isCut ? .move : .copy)
    }

    /// NSWorkspace.recycle は複数件を一度に捨てると先頭の1件しか「戻す」が効かないため Finder に任せる
    static func trash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let script = """
            on run argv
                set targets to {}
                repeat with p in argv
                    set end of targets to (POSIX file (contents of p)) as alias
                end repeat
                tell application "Finder" to delete targets
            end run
            """
        Task.detached {
            let process = Process()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script] + urls.map(\.path)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderr
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    await showError("ゴミ箱に移動できませんでした\n\(message)")
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
