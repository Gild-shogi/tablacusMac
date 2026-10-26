import Foundation
import Testing
@testable import TablacusMac

@MainActor
@Test func フォルダを開くと中身を読み込み_閉じると中で開いていたフォルダと選択も閉じる() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let inner = root.appendingPathComponent("a/b")
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    try "x".write(to: inner.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
    let tab = Tab(root)
    let a = tab.items[0].url

    tab.setExpanded(a, true)
    let b = try #require(tab.children[a]?.first).url
    tab.setExpanded(b, true)
    #expect(tab.children[b]?.map(\.name) == ["c.txt"])
    tab.selection = [b.appendingPathComponent("c.txt")]

    tab.setExpanded(a, false)

    #expect(tab.expanded.isEmpty)
    #expect(tab.children.isEmpty)
    #expect(tab.selection.isEmpty)
}
