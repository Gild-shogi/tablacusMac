import Foundation
import Testing
@testable import TablacusMac

private func makeTemporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func 同名の項目があるとき上書きせず名前の後ろにハイフンと番号を付けてコピーする() throws {
    let root = try makeTemporaryFolder()
    let source = try makeTemporaryFolder()
    try "元".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "新".write(to: source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

    try transfer([source.appendingPathComponent("a.txt")], to: root, .copy)
    try transfer([source.appendingPathComponent("a.txt")], to: root, .copy)

    #expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "元")
    #expect(try String(contentsOf: root.appendingPathComponent("a-1.txt"), encoding: .utf8) == "新")
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a-2.txt").path))
}

@Test func フォルダを自分の配下へ移動しようとするとエラーになり元のまま残る() throws {
    let root = try makeTemporaryFolder()
    let parent = root.appendingPathComponent("parent")
    let child = parent.appendingPathComponent("child")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

    #expect(throws: FileOperationError.self) { try transfer([parent], to: child, .move) }
    #expect(FileManager.default.fileExists(atPath: child.path))
}

@Test func 同じフォルダへの移動は何もしない() throws {
    let root = try makeTemporaryFolder()
    let file = root.appendingPathComponent("a.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)

    try transfer([file], to: root, .move)

    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["a.txt"])
}
