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

@Test func 選択中のフォルダがあればその中へ貼り付け_貼り付ける項目自身なら表示中のフォルダへ複製する() {
    let current = URL(fileURLWithPath: "/work")
    let selected = URL(fileURLWithPath: "/work/sub/", isDirectory: true)
    let file = URL(fileURLWithPath: "/other/a.txt")

    #expect(pasteDestination(for: [file], current: current, selectedFolder: selected) == selected)
    #expect(pasteDestination(for: [URL(fileURLWithPath: "/work/sub")], current: current, selectedFolder: selected) == current)
    #expect(pasteDestination(for: [file], current: current, selectedFolder: nil) == current)
}

@Test func 複製をさらに複製すると番号が続きになり_元の名前がなければ名前の一部として扱う() throws {
    let root = try makeTemporaryFolder()
    for name in ["a.txt", "a-1.txt", "report-2024.pdf"] {
        try "x".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    try transfer([root.appendingPathComponent("a-1.txt")], to: root, .copy)
    try transfer([root.appendingPathComponent("report-2024.pdf")], to: root, .copy)

    let names = Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
    #expect(names == ["a.txt", "a-1.txt", "a-2.txt", "report-2024.pdf", "report-2024-1.pdf"])
}
