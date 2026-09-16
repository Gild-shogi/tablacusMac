import AppKit

enum FileOperation: Sendable {
    case copy, move
}

struct FileOperationError: LocalizedError {
    let errorDescription: String?
}

/// 同名の項目があれば「名前-1.拡張子」「名前-2.拡張子」…の形で空いている名前を返す
func uniqueURL(for name: String, in folder: URL) -> URL {
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var candidate = folder.appendingPathComponent(name)
    var number = 1
    while FileManager.default.fileExists(atPath: candidate.path) {
        let numbered = "\(base)-\(number)"
        candidate = folder.appendingPathComponent(ext.isEmpty ? numbered : "\(numbered).\(ext)")
        number += 1
    }
    return candidate
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

    static func paste(into folder: URL) {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        let isCut = Set(urls.map(\.path)) == cutPaths
        if isCut { cutPaths = [] }
        perform(urls, to: folder, isCut ? .move : .copy)
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
