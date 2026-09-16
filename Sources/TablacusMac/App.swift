import SwiftUI

@main
struct TablacusMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @FocusedValue(\.browser) private var browser

    var body: some Scene {
        WindowGroup {
            BrowserView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("新しいタブ") { browser?.active.newTab() }
                    .keyboardShortcut("t")
                // 標準の「閉じる」より前に置くことで ⌘W をタブ閉じに割り当てる
                Button("タブを閉じる") { if let browser { browser.active.close(browser.tab) } }
                    .keyboardShortcut("w")
            }
            CommandGroup(after: .sidebar) {
                Button("画面分割") { browser?.toggleSplit() }
                    .keyboardShortcut("\\")
            }
            CommandMenu("移動") {
                Button("戻る") { browser?.tab.goBack() }.keyboardShortcut("[")
                Button("進む") { browser?.tab.goForward() }.keyboardShortcut("]")
                Button("上の階層") { browser?.tab.goUp() }.keyboardShortcut(.upArrow)
                Button("再読み込み") { browser?.tab.reload() }.keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // .app バンドル外（swift run）で起動すると前面に出ずキー入力も受けないため
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct BrowserKey: FocusedValueKey {
    typealias Value = Browser
}

extension FocusedValues {
    var browser: Browser? {
        get { self[BrowserKey.self] }
        set { self[BrowserKey.self] = newValue }
    }
}
