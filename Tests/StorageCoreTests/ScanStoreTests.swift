import Foundation
import Testing
@testable import StorageCore

private func sampleTree() -> FileTree {
    var tree = FileTree(rootPath: "/data", scanDate: Date(timeIntervalSince1970: 1_790_000_000.25))
    let dir = tree.append(name: "Vidéos", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 100)
    tree.append(name: "film.mov", parent: dir, type: .file, kind: .video, size: 7_000, modDate: 101)
    let gone = tree.append(name: "supprimé.bin", parent: dir, type: .file, kind: .other, size: 500, modDate: 102)
    tree.append(name: "Outil.app", parent: tree.root, type: .package, kind: .app, size: 3_000, modDate: 103)
    tree.unreadablePaths = ["/data/verrou"]
    tree.finalize()
    tree.remove([gone])
    return tree
}

@Suite struct ScanStoreTests {
    @Test func savesAndLoadsAnIdenticalTree() throws {
        let tmp = try TempDir()
        let store = ScanStore(directory: URL(fileURLWithPath: tmp.path + "/support"))
        let original = sampleTree()

        try store.save(original)
        let loaded = try #require(try store.load())

        #expect(loaded.rootPath == "/data")
        #expect(loaded.scanDate == original.scanDate)
        #expect(loaded.unreadablePaths == ["/data/verrou"])
        #expect(loaded.liveNodeCount == original.liveNodeCount)
        #expect(loaded.totalSize == original.totalSize)
        for path in ["/data/Vidéos", "/data/Vidéos/film.mov", "/data/Outil.app"] {
            let a = try #require(original.node(atPath: path))
            let b = try #require(loaded.node(atPath: path))
            #expect(loaded.size(of: b) == original.size(of: a))
            #expect(loaded.nodeType(of: b) == original.nodeType(of: a))
            #expect(loaded.kind(of: b) == original.kind(of: a))
            #expect(loaded.modificationDate(of: b) == original.modificationDate(of: a))
        }
        #expect(loaded.node(atPath: "/data/Vidéos/supprimé.bin") == nil)
        let rootChildren = loaded.children(of: loaded.root).map { loaded.name(of: $0) }
        #expect(rootChildren == ["Vidéos", "Outil.app"])
    }

    @Test func loadReturnsNilWithoutASavedScan() throws {
        let tmp = try TempDir()
        let store = ScanStore(directory: URL(fileURLWithPath: tmp.path))
        #expect(try store.load() == nil)
    }

    @Test func rejectsCorruptedFiles() throws {
        let tmp = try TempDir()
        let store = ScanStore(directory: URL(fileURLWithPath: tmp.path))
        try Data([1, 2, 3, 4, 5]).write(to: store.fileURL)
        #expect(throws: ScanStoreError.corrupted) { try store.load() }
    }

    @Test func rejectsTruncatedData() throws {
        let raw = ScanStore.encode(sampleTree())
        #expect(throws: ScanStoreError.corrupted) { try ScanStore.decode(raw.prefix(raw.count - 3)) }
    }

    @Test func rejectsOtherFormatVersions() throws {
        var raw = ScanStore.encode(sampleTree())
        raw[4] = 99
        #expect(throws: ScanStoreError.unsupportedVersion(99)) { try ScanStore.decode(raw) }
    }
}
