import AppKit

enum WezTerm {
    private static let bundleID = "com.github.wez.wezterm"

    @MainActor
    static func open(_ folder: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            FileOperations.showError("WezTerm がインストールされていません")
            return
        }
        let arguments = ["start", "--new-tab", "--cwd", folder.path]
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        Task.detached {
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                // 起動中のアプリには起動引数が渡らないため、CLI で既存ウィンドウにタブを足してから前面に出す
                if isRunning {
                    try run(app.appendingPathComponent("Contents/MacOS/wezterm"), arguments)
                } else {
                    configuration.arguments = arguments
                }
                _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            } catch {
                let message = error.localizedDescription
                await FileOperations.showError(message)
            }
        }
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FileOperationError(errorDescription: "WezTerm で開けませんでした\n\(String(decoding: data, as: UTF8.self))")
        }
    }
}
