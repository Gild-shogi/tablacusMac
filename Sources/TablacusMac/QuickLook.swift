import Quartz
import SwiftUI

/// Finder と同じくスペース・⌘Y で選択項目をクイックルックする
@MainActor
final class QuickLook: NSResponder, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var urls: [URL] = []

    static func toggle(_ urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else if !urls.isEmpty {
            shared.urls = urls
            panel.updateController()
            // キーウィンドウにしないことで、表示中も一覧の矢印キーで項目を切り替えられる
            panel.orderFront(nil)
        }
    }

    static func update(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        shared.urls = urls
        panel.reloadData()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { MainActor.assumeIsolated { panel.dataSource = self } }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { MainActor.assumeIsolated { panel.dataSource = nil } }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { urls[index] as NSURL }
}

/// パネルはキーウィンドウのレスポンダチェーンから操作役を探すため、ウィンドウの次に QuickLook を挟む
/// ponytail: 共有の1つを最後に開いたウィンドウへ挟む。複数ウィンドウで効かない窓が出たらウィンドウごとに作る
struct QuickLookResponder: NSViewRepresentable {
    func makeNSView(context: Context) -> InstallerView { InstallerView() }
    func updateNSView(_ view: InstallerView, context: Context) {}

    final class InstallerView: NSView {
        override func viewDidMoveToWindow() {
            guard let window, window.nextResponder !== QuickLook.shared else { return }
            QuickLook.shared.nextResponder = window.nextResponder
            window.nextResponder = QuickLook.shared
        }
    }
}
