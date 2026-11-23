import CoreGraphics
import Testing
@testable import StorageCore

@Suite struct TreemapSceneTests {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func topLevelItemsMatchChildren() {
        var tree = FileTree(rootPath: "/r")
        let a = tree.append(name: "a.mov", parent: tree.root, type: .file, kind: .video, size: 500, modDate: 0)
        let b = tree.append(name: "b.pdf", parent: tree.root, type: .file, kind: .document, size: 300, modDate: 0)
        let c = tree.append(name: "c.zip", parent: tree.root, type: .file, kind: .archive, size: 200, modDate: 0)
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds)
        #expect(items.map(\.node) == [a, b, c])
        #expect(items.allSatisfy { $0.depth == 0 })
        #expect(items[0].label == "a.mov")
        #expect(items[0].kind == .video)
        #expect(items[0].size == 500)
    }

    @Test func tinyChildrenAreGroupedIntoOneBlock() {
        var tree = FileTree(rootPath: "/r")
        let big = tree.append(name: "big", parent: tree.root, type: .file, kind: .other, size: 1_000_000, modDate: 0)
        for i in 0..<50 {
            tree.append(name: "t\(i)", parent: tree.root, type: .file, kind: .other, size: 1, modDate: 0)
        }
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds)
        #expect(items.count == 2)
        #expect(items[0].node == big)
        #expect(items[1].content == .smallItems(count: 50))
        #expect(items[1].label == "50 petits éléments")
        #expect(items[1].size == 50)
    }

    @Test func largeDirectoriesShowTheirChildrenInside() {
        var tree = FileTree(rootPath: "/r")
        let dir = tree.append(name: "dir", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 0)
        let x = tree.append(name: "x.png", parent: dir, type: .file, kind: .image, size: 600, modDate: 0)
        let y = tree.append(name: "y.png", parent: dir, type: .file, kind: .image, size: 400, modDate: 0)
        let pkg = tree.append(name: "App.app", parent: tree.root, type: .package, kind: .app, size: 1000, modDate: 0)
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds)
        let parentRect = try! #require(items.first { $0.node == dir }).rect
        let nested = items.filter { $0.depth == 1 }
        #expect(nested.map(\.node) == [x, y])
        for item in nested {
            #expect(parentRect.contains(item.rect))
            #expect(item.rect.minY >= parentRect.minY + TreemapScene.headerHeight - 0.01)
        }
        // Un paquet n'est jamais ouvert.
        #expect(!items.contains { $0.depth == 1 && tree.parent(of: $0.node ?? 0) == pkg })
    }

    @Test func systemOtherBlockIsAddedAtTheRoot() {
        var tree = FileTree(rootPath: "/")
        tree.append(name: "Users", parent: tree.root, type: .file, kind: .other, size: 700, modDate: 0)
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds, systemOtherSize: 300)
        let other = try! #require(items.first { $0.content == .systemOther })
        #expect(other.label == "Système et autres")
        #expect(other.kind == .system)
        let ratio = Double(other.rect.width * other.rect.height) / Double(bounds.width * bounds.height)
        #expect(abs(ratio - 0.3) < 0.01)
    }

    @Test func emptyDirectoryGivesNoItems() {
        let tree = FileTree(rootPath: "/vide")
        #expect(TreemapScene.build(tree: tree, node: tree.root, in: bounds).isEmpty)
    }

    @Test func hitTestReturnsTheDeepestItem() {
        var tree = FileTree(rootPath: "/r")
        let dir = tree.append(name: "dir", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 0)
        let only = tree.append(name: "only.bin", parent: dir, type: .file, kind: .other, size: 10, modDate: 0)
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds)
        let inside = CGPoint(x: bounds.midX, y: bounds.midY)
        #expect(TreemapScene.hitTest(inside, in: items)?.node == only)
        let header = CGPoint(x: bounds.midX, y: 4)
        #expect(TreemapScene.hitTest(header, in: items)?.node == dir)
        #expect(TreemapScene.hitTest(CGPoint(x: -5, y: -5), in: items) == nil)
    }
}
