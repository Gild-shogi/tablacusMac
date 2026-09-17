import Foundation
import Testing
@testable import TablacusMac

@MainActor
@Test func 絞り込みはすべての語を含む項目だけを表示し_見えなくなった項目は選択から外す() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for name in ["Report 2024.pdf", "report-draft.txt", "photo.png"] {
        try "x".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let tab = Tab(root)
    tab.selection = Set(tab.items.map(\.id))

    tab.filter = "REPORT pdf"

    #expect(tab.visibleItems.map(\.name) == ["Report 2024.pdf"])
    #expect(tab.selection == Set(tab.visibleItems.map(\.id)))
}
