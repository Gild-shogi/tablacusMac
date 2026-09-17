import Foundation
import Testing
@testable import TablacusMac

@MainActor
@Test func 保存した状態から復元するとレイアウト_タブ_選択中のタブ_操作中のペインが戻る() throws {
    let browser = Browser()
    browser.setLayout(.columns)
    let right = browser.visiblePanes[1]
    right.newTab(FileManager.default.temporaryDirectory)
    right.newTab(URL(fileURLWithPath: "/"))
    right.selectedID = right.tabs[1].id
    browser.activeID = right.id

    let saved = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(browser.state))
    let restored = Browser(restoring: saved)

    #expect(restored.state == browser.state)
    #expect(restored.layout == .columns)
    #expect(restored.tab.url.path == browser.tab.url.path)
}
