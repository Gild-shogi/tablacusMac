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
                Button("新規フォルダ") { browser?.tab.createFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            // SwiftUI の onCopyCommand が書くクリップボードは貼り付け時にパスとして読めなかったため、自前で書き込む
            CommandGroup(replacing: .pasteboard) {
                Button("カット") { onFiles(or: #selector(NSText.cut(_:))) { FileOperations.copy(Array($0.selection), cut: true) } }
                    .keyboardShortcut("x")
                Button("コピー") { onFiles(or: #selector(NSText.copy(_:))) { FileOperations.copy(Array($0.selection), cut: false) } }
                    .keyboardShortcut("c")
                Button("ペースト") { onFiles(or: #selector(NSText.paste(_:))) { FileOperations.paste(into: $0.url, selectedFolder: $0.selectedFolder) } }
                    .keyboardShortcut("v")
                Button("すべてを選択") { NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil) }
                    .keyboardShortcut("a")
            }
            CommandGroup(after: .textEditing) {
                Button("絞り込み") { browser?.tab.wantsFilterFocus = true }
                    .keyboardShortcut("f")
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(Layout.allCases.enumerated()), id: \.element) { index, layout in
                    Toggle(layout.rawValue, isOn: Binding(get: { browser?.layout == layout }, set: { _ in browser?.setLayout(layout) }))
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                }
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

extension TablacusMacApp {
    /// パス欄などで文字を編集中ならテキストの編集操作として送り、それ以外は操作中のタブのファイルを扱う
    private func onFiles(or textAction: Selector, _ action: (Tab) -> Void) {
        if let browser, !(NSApp.keyWindow?.firstResponder is NSText) {
            action(browser.tab)
        } else {
            NSApp.sendAction(textAction, to: nil, from: nil)
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
