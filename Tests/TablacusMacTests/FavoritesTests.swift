import Foundation
import Testing
@testable import TablacusMac

@MainActor
@Test func フォルダだけを重複なくドロップ位置に追加し_再起動後も残る() throws {
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = root.appendingPathComponent("a")
    let b = root.appendingPathComponent("b")
    let file = root.appendingPathComponent("f.txt")
    try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    try "x".write(to: file, atomically: true, encoding: .utf8)

    let favorites = Favorites(defaults: defaults)
    let initialCount = favorites.urls.count
    favorites.insert([a], at: 0)
    favorites.insert([b, file, a, b], at: 1)

    let reloaded = Favorites(defaults: defaults)
    #expect(reloaded.urls.prefix(2).map(\.path) == [a.path, b.path])
    #expect(reloaded.urls.count == initialCount + 2)
}
