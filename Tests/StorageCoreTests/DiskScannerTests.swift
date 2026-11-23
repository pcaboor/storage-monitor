import Foundation
import Testing
@testable import StorageCore

@Suite struct DiskScannerTests {
    @Test func buildsTheTreeWithAllocatedSizes() async throws {
        let tmp = try TempDir()
        let f1 = try tmp.file("a/one.bin", bytes: 10_000)
        let f2 = try tmp.file("a/b/two.bin", bytes: 5_000)
        let f3 = try tmp.file("three.txt", bytes: 1)

        let tree = try await DiskScanner().scan(root: tmp.path)

        #expect(tree.rootPath == tmp.path)
        #expect(tree.totalSize == allocatedSize(f1) + allocatedSize(f2) + allocatedSize(f3))
        let a = try #require(tree.node(atPath: tmp.path + "/a"))
        #expect(tree.nodeType(of: a) == .directory)
        #expect(tree.size(of: a) == allocatedSize(f1) + allocatedSize(f2))
        let two = try #require(tree.node(atPath: f2))
        #expect(tree.nodeType(of: two) == .file)
        #expect(tree.size(of: two) == allocatedSize(f2))
        #expect(tree.children(of: tree.root).first == a)
        #expect(tree.unreadablePaths.isEmpty)
    }

    @Test func countsHardLinksOnce() async throws {
        let tmp = try TempDir()
        let original = try tmp.file("x.bin", bytes: 100_000)
        try FileManager.default.linkItem(atPath: original, toPath: tmp.path + "/y.bin")

        let tree = try await DiskScanner().scan(root: tmp.path)

        #expect(tree.node(atPath: original) != nil)
        #expect(tree.node(atPath: tmp.path + "/y.bin") != nil)
        #expect(tree.totalSize == allocatedSize(original))
    }

    @Test func ignoresSymlinks() async throws {
        let tmp = try TempDir()
        let target = try tmp.file("cible.bin", bytes: 50_000)
        try FileManager.default.createSymbolicLink(atPath: tmp.path + "/lien", withDestinationPath: target)

        let tree = try await DiskScanner().scan(root: tmp.path)

        #expect(tree.node(atPath: tmp.path + "/lien") == nil)
        #expect(tree.totalSize == allocatedSize(target))
    }

    @Test func measuresSparseFilesByAllocatedSize() async throws {
        let tmp = try TempDir()
        let path = tmp.path + "/creux.raw"
        FileManager.default.createFile(atPath: path, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.seek(toOffset: 50_000_000)
        try handle.write(contentsOf: Data([1]))
        try handle.close()

        let tree = try await DiskScanner().scan(root: tmp.path)

        let node = try #require(tree.node(atPath: path))
        #expect(tree.size(of: node) == allocatedSize(path))
        #expect(tree.size(of: node) < 1_000_000)
    }

    @Test func treatsPackagesAsLeaves() async throws {
        let tmp = try TempDir()
        let binary = try tmp.file("Outil.app/Contents/MacOS/outil", bytes: 20_000)
        let plist = try tmp.file("Outil.app/Contents/Info.plist", bytes: 300)

        let tree = try await DiskScanner().scan(root: tmp.path)

        let app = try #require(tree.node(atPath: tmp.path + "/Outil.app"))
        #expect(tree.nodeType(of: app) == .package)
        #expect(tree.kind(of: app) == .app)
        #expect(tree.children(of: app).isEmpty)
        #expect(tree.size(of: app) == allocatedSize(binary) + allocatedSize(plist))
    }

    @Test func recordsUnreadableDirectories() async throws {
        let tmp = try TempDir()
        let locked = try tmp.dir("verrou")
        try tmp.file("verrou/cache.bin", bytes: 1_000)
        chmod(locked, 0o000)
        defer { chmod(locked, 0o755) }

        let tree = try await DiskScanner().scan(root: tmp.path)

        #expect(tree.unreadablePaths == [locked])
        #expect(tree.node(atPath: locked) != nil)
    }

    @Test func skipsExcludedPaths() async throws {
        let tmp = try TempDir()
        try tmp.file("garde/f.bin", bytes: 1_000)
        try tmp.file("ignore/f.bin", bytes: 1_000)

        let tree = try await DiskScanner(excludedPaths: [tmp.path + "/ignore"]).scan(root: tmp.path)

        #expect(tree.node(atPath: tmp.path + "/garde") != nil)
        #expect(tree.node(atPath: tmp.path + "/ignore") == nil)
    }

    @Test func throwsWhenTheRootIsUnreadable() async throws {
        let tmp = try TempDir()
        let missing = tmp.path + "/absent"
        await #expect(throws: ScanError.rootUnreadable(path: missing, errno: ENOENT)) {
            try await DiskScanner().scan(root: missing)
        }
    }

    @Test func stopsWhenCancelled() async throws {
        let tmp = try TempDir()
        for i in 0..<200 { try tmp.file("d\(i)/f.bin", bytes: 10) }
        let root = tmp.path

        let task = Task { try await DiskScanner().scan(root: root) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func reportsProgress() async throws {
        let tmp = try TempDir()
        try tmp.file("a/f.bin", bytes: 4_096)
        let last = LockedBox<ScanProgress?>(nil)

        let tree = try await DiskScanner().scan(root: tmp.path) { last.value = $0 }

        let progress = try #require(last.value)
        #expect(progress.entryCount == 2)
        #expect(progress.byteCount == tree.totalSize)
    }
}
