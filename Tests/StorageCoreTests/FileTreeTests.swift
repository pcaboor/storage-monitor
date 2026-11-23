import Foundation
import Testing
@testable import StorageCore

/// /data
/// ├── videos/          (dossier)
/// │   ├── a.mp4  600
/// │   └── b.mp4  300
/// ├── notes.txt  50
/// └── code/            (dossier)
///     └── main.swift 100
private func sampleTree() -> (tree: FileTree, videos: NodeID, a: NodeID, b: NodeID, notes: NodeID, code: NodeID, main: NodeID) {
    var tree = FileTree(rootPath: "/data")
    let videos = tree.append(name: "videos", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 10)
    let a = tree.append(name: "a.mp4", parent: videos, type: .file, kind: .video, size: 600, modDate: 11)
    let b = tree.append(name: "b.mp4", parent: videos, type: .file, kind: .video, size: 300, modDate: 12)
    let notes = tree.append(name: "notes.txt", parent: tree.root, type: .file, kind: .document, size: 50, modDate: 13)
    let code = tree.append(name: "code", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 14)
    let main = tree.append(name: "main.swift", parent: code, type: .file, kind: .code, size: 100, modDate: 15)
    tree.finalize()
    return (tree, videos, a, b, notes, code, main)
}

@Suite struct FileTreeTests {
    @Test func finalizeAggregatesSizesAndSortsChildren() {
        let s = sampleTree()
        #expect(s.tree.size(of: s.videos) == 900)
        #expect(s.tree.size(of: s.code) == 100)
        #expect(s.tree.totalSize == 1050)
        #expect(s.tree.children(of: s.tree.root) == [s.videos, s.code, s.notes])
        #expect(s.tree.children(of: s.videos) == [s.a, s.b])
    }

    @Test func directoriesTakeTheirDominantKind() {
        let s = sampleTree()
        #expect(s.tree.kind(of: s.videos) == .video)
        #expect(s.tree.kind(of: s.code) == .code)
        #expect(s.tree.kind(of: s.tree.root) == .video)
    }

    @Test func pathsRoundTrip() {
        let s = sampleTree()
        #expect(s.tree.path(of: s.tree.root) == "/data")
        #expect(s.tree.path(of: s.main) == "/data/code/main.swift")
        #expect(s.tree.node(atPath: "/data/code/main.swift") == s.main)
        #expect(s.tree.node(atPath: "/data") == s.tree.root)
        #expect(s.tree.node(atPath: "/data/absent") == nil)
        #expect(s.tree.node(atPath: "/autre/code") == nil)
    }

    @Test func pathsUnderTheFilesystemRoot() {
        var tree = FileTree(rootPath: "/")
        let users = tree.append(name: "Users", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 0)
        let file = tree.append(name: "f.txt", parent: users, type: .file, kind: .document, size: 1, modDate: 0)
        tree.finalize()
        #expect(tree.path(of: file) == "/Users/f.txt")
        #expect(tree.node(atPath: "/Users/f.txt") == file)
        #expect(tree.node(atPath: "/") == tree.root)
    }

    @Test func ancestorsGoFromRootToNode() {
        let s = sampleTree()
        #expect(s.tree.ancestors(of: s.main) == [s.tree.root, s.code, s.main])
        #expect(s.tree.ancestors(of: s.tree.root) == [s.tree.root])
        #expect(s.tree.parent(of: s.tree.root) == nil)
        #expect(s.tree.parent(of: s.a) == s.videos)
    }

    @Test func modificationDateIsExposedAsDate() {
        let s = sampleTree()
        #expect(s.tree.modificationDate(of: s.a) == Date(timeIntervalSince1970: 11))
    }

    @Test func removeUpdatesAncestorsAndDetaches() {
        var s = sampleTree()
        s.tree.remove([s.a])
        #expect(s.tree.isRemoved(s.a))
        #expect(s.tree.size(of: s.videos) == 300)
        #expect(s.tree.totalSize == 450)
        #expect(s.tree.children(of: s.videos) == [s.b])
        // videos (300) dépasse toujours code (100) : l'ordre est recalculé.
        #expect(s.tree.children(of: s.tree.root) == [s.videos, s.code, s.notes])
        #expect(s.tree.liveNodeCount == 6)
    }

    @Test func removingADirectoryRemovesItsDescendants() {
        var s = sampleTree()
        s.tree.remove([s.videos])
        #expect(s.tree.isRemoved(s.videos))
        #expect(s.tree.isRemoved(s.a))
        #expect(s.tree.isRemoved(s.b))
        #expect(s.tree.totalSize == 150)
        #expect(s.tree.children(of: s.tree.root) == [s.code, s.notes])
        #expect(s.tree.kind(of: s.tree.root) == .code)
        // Supprimer deux fois ne change rien.
        s.tree.remove([s.videos, s.a])
        #expect(s.tree.totalSize == 150)
    }

    @Test func removeIgnoresTheRoot() {
        var s = sampleTree()
        s.tree.remove([s.tree.root])
        #expect(!s.tree.isRemoved(s.tree.root))
        #expect(s.tree.totalSize == 1050)
    }

    @Test func replaceSubtreeGraftsAFreshScan() {
        var s = sampleTree()
        s.tree.unreadablePaths = ["/data/code/secret", "/data/other"]

        var fresh = FileTree(rootPath: "/data/code")
        let lib = fresh.append(name: "lib", parent: fresh.root, type: .directory, kind: .other, size: 0, modDate: 20)
        fresh.append(name: "big.swift", parent: lib, type: .file, kind: .code, size: 2000, modDate: 21)
        fresh.append(name: "small.swift", parent: fresh.root, type: .file, kind: .code, size: 10, modDate: 22)
        fresh.unreadablePaths = ["/data/code/new-locked"]
        fresh.finalize()

        s.tree.replaceSubtree(at: s.code, with: fresh)

        #expect(s.tree.isRemoved(s.main))
        #expect(s.tree.size(of: s.code) == 2010)
        #expect(s.tree.totalSize == 2960)
        let big = try! #require(s.tree.node(atPath: "/data/code/lib/big.swift"))
        #expect(s.tree.size(of: big) == 2000)
        #expect(s.tree.children(of: s.tree.root).first == s.code)
        #expect(s.tree.unreadablePaths == ["/data/code/new-locked", "/data/other"])
    }
}
