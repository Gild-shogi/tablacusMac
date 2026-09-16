import Testing
@testable import TablacusMac

@MainActor
@Test func 画面数を減らして戻すと隠れていたペインがそのまま再表示される() {
    let browser = Browser()
    browser.setLayout(.grid)
    let ids = browser.visiblePanes.map(\.id)
    browser.activeID = ids[3]

    browser.setLayout(.single)
    #expect(browser.active.id == ids[0])

    browser.setLayout(.grid)
    #expect(browser.visiblePanes.map(\.id) == ids)
}
