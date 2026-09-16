import AppKit

/// Orca は登録済みリポジトリ（worktree）のルートでしか端末を作れないため、フォルダを含む worktree を探す
func containingWorktree(of folder: String, in worktrees: [String]) -> String? {
    worktrees
        .filter { folder == $0 || folder.hasPrefix($0 + "/") }
        .max { $0.count < $1.count }
}

/// 端末へキー入力として送られるので、制御文字（⌃U や改行で別コマンドを実行できる）を含むパスは拒否する
func cdCommand(to path: String) -> String? {
    guard !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else { return nil }
    return "cd '" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

enum Orca {
    private struct WorktreeList: Decodable {
        struct Result: Decodable { let worktrees: [Worktree] }
        struct Worktree: Decodable { let path: String }
        let result: Result
    }

    @MainActor
    static func open(_ folder: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.stablyai.orca") else {
            FileOperations.showError("Orca がインストールされていません")
            return
        }
        let path = folder.standardizedFileURL.path
        Task.detached {
            do {
                let list = try JSONDecoder().decode(WorktreeList.self, from: run(app, ["worktree", "list", "--limit", "10000", "--json"]))
                guard let root = containingWorktree(of: path, in: list.result.worktrees.map(\.path)) else {
                    await FileOperations.showError("「\(path)」は Orca に登録されたリポジトリの外にあります")
                    return
                }
                var arguments = ["terminal", "create", "--worktree", "path:\(root)", "--focus", "--json"]
                if path != root {
                    guard let cd = cdCommand(to: path) else {
                        await FileOperations.showError("制御文字を含むパスは Orca で開けません")
                        return
                    }
                    arguments += ["--command", cd]
                }
                _ = try run(app, arguments)
                _ = try await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                let message = error.localizedDescription
                await FileOperations.showError(message)
            }
        }
    }

    /// /usr/local/bin/orca は GUI アプリの PATH に無く、中身も Orca.app 内の CLI を Node として起動するだけなので直接呼ぶ
    private static func run(_ app: URL, _ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = app.appendingPathComponent("Contents/MacOS/Orca")
        process.arguments = [app.appendingPathComponent("Contents/Resources/app.asar.unpacked/out/cli/index.js").path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["ELECTRON_RUN_AS_NODE": "1"]) { $1 }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FileOperationError(errorDescription: "Orca の呼び出しに失敗しました\n\(String(decoding: data, as: UTF8.self))")
        }
        return data
    }
}
