import Foundation
import Testing
@testable import TablacusMac

@MainActor
@Test func 保存した並び順を読み込むと同じ列と向きで戻る() throws {
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    #expect(SortPreference.load(defaults).first?.keyPath == \FileItem.name)

    SortPreference.save([KeyPathComparator(\FileItem.modified, order: .reverse)], defaults)
    let restored = try #require(SortPreference.load(defaults).first)

    #expect(restored.keyPath == \FileItem.modified)
    #expect(restored.order == .reverse)
}
