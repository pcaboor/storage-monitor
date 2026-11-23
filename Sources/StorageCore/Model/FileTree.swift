import Foundation

public typealias NodeID = Int32

/// Arbre compact des fichiers et dossiers scannés (tableaux parallèles indexés par `NodeID`).
///
/// Invariant : l'index d'un enfant est toujours strictement supérieur à celui de son parent.
/// Les nœuds supprimés restent dans les tableaux, marqués `removed`, et sont détachés de leur parent.
public struct FileTree: Sendable {
    public static let noParent: NodeID = -1

    public let rootPath: String
    public var scanDate: Date
    public var unreadablePaths: [String]

    private(set) var names: [String]
    private(set) var parents: [NodeID]
    private(set) var types: [NodeType]
    private(set) var kinds: [ContentKind]
    private(set) var sizes: [UInt64]
    private(set) var modDates: [Int64]
    private(set) var childLists: [[NodeID]]
    private(set) var removedFlags: [Bool]

    public var root: NodeID { 0 }

    public init(rootPath: String, scanDate: Date = Date()) {
        self.rootPath = rootPath
        self.scanDate = scanDate
        unreadablePaths = []
        names = [rootPath]
        parents = [Self.noParent]
        types = [.directory]
        kinds = [.other]
        sizes = [0]
        modDates = [0]
        childLists = [[]]
        removedFlags = [false]
    }

    /// Reconstruit un arbre à partir de tableaux en pré-ordre (utilisé par la persistance).
    init(rootPath: String, scanDate: Date, unreadablePaths: [String],
         names: [String], parents: [NodeID], types: [NodeType], kinds: [ContentKind],
         sizes: [UInt64], modDates: [Int64]) {
        self.rootPath = rootPath
        self.scanDate = scanDate
        self.unreadablePaths = unreadablePaths
        self.names = names
        self.parents = parents
        self.types = types
        self.kinds = kinds
        self.sizes = sizes
        self.modDates = modDates
        removedFlags = [Bool](repeating: false, count: names.count)
        var lists = [[NodeID]](repeating: [], count: names.count)
        for i in 1..<max(names.count, 1) { lists[Int(parents[i])].append(NodeID(i)) }
        childLists = lists
    }

    // MARK: - Construction

    @discardableResult
    public mutating func append(name: String, parent: NodeID, type: NodeType, kind: ContentKind,
                                size: UInt64, modDate: Int64) -> NodeID {
        let id = NodeID(names.count)
        names.append(name)
        parents.append(parent)
        types.append(type)
        kinds.append(kind)
        sizes.append(size)
        modDates.append(modDate)
        childLists.append([])
        removedFlags.append(false)
        childLists[Int(parent)].append(id)
        return id
    }

    public mutating func setSize(_ size: UInt64, of node: NodeID) {
        sizes[Int(node)] = size
    }

    /// Calcule la taille cumulée et le type dominant de chaque dossier,
    /// et trie les enfants par taille décroissante. À appeler une fois la construction terminée.
    public mutating func finalize() {
        for i in stride(from: names.count - 1, through: 0, by: -1)
        where types[i] == .directory && !removedFlags[i] {
            var total: UInt64 = 0
            for c in childLists[i] { total += sizes[Int(c)] }
            sizes[i] = total
            sortChildren(of: NodeID(i))
            kinds[i] = dominantKind(of: NodeID(i))
        }
    }

    // MARK: - Lecture

    /// Nombre d'emplacements, nœuds supprimés compris.
    public var storageCount: Int { names.count }
    public var liveNodeCount: Int { removedFlags.lazy.filter { !$0 }.count }
    public var totalSize: UInt64 { sizes[0] }

    public func name(of node: NodeID) -> String { names[Int(node)] }
    public func size(of node: NodeID) -> UInt64 { sizes[Int(node)] }
    public func nodeType(of node: NodeID) -> NodeType { types[Int(node)] }
    public func kind(of node: NodeID) -> ContentKind { kinds[Int(node)] }
    public func isRemoved(_ node: NodeID) -> Bool { removedFlags[Int(node)] }
    public func children(of node: NodeID) -> [NodeID] { childLists[Int(node)] }

    public func modificationDate(of node: NodeID) -> Date {
        Date(timeIntervalSince1970: TimeInterval(modDates[Int(node)]))
    }

    public func parent(of node: NodeID) -> NodeID? {
        let p = parents[Int(node)]
        return p == Self.noParent ? nil : p
    }

    /// Chaîne de la racine jusqu'au nœud inclus.
    public func ancestors(of node: NodeID) -> [NodeID] {
        var chain: [NodeID] = [node]
        var cur = node
        while let p = parent(of: cur) { chain.append(p); cur = p }
        return chain.reversed()
    }

    public func path(of node: NodeID) -> String {
        if node == root { return rootPath }
        var comps: [String] = []
        var cur = node
        while cur != root {
            comps.append(names[Int(cur)])
            cur = parents[Int(cur)]
        }
        let relative = comps.reversed().joined(separator: "/")
        return rootPath == "/" ? "/" + relative : rootPath + "/" + relative
    }

    public func node(atPath path: String) -> NodeID? {
        if path == rootPath { return root }
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        var cur = root
        for comp in path.dropFirst(prefix.count).split(separator: "/") {
            guard let next = childLists[Int(cur)].first(where: { names[Int($0)] == comp }) else { return nil }
            cur = next
        }
        return cur
    }

    // MARK: - Mutations

    /// Retire des nœuds (et leurs descendants) et met à jour les tailles des ancêtres.
    public mutating func remove(_ nodes: [NodeID]) {
        for node in nodes {
            let i = Int(node)
            guard node != root, !removedFlags[i] else { continue }
            let size = sizes[i]
            let parent = parents[i]
            markRemoved(node)
            childLists[Int(parent)].removeAll { $0 == node }
            adjustAncestors(startingAt: parent, delta: -Int64(size))
        }
    }

    /// Remplace le contenu d'un dossier par un sous-arbre fraîchement scanné du même chemin.
    public mutating func replaceSubtree(at node: NodeID, with sub: FileTree) {
        let n = Int(node)
        let nodePath = path(of: node)
        for c in childLists[n] { markRemoved(c) }
        childLists[n] = []

        var map = [NodeID](repeating: Self.noParent, count: sub.storageCount)
        map[0] = node
        for i in 1..<max(sub.storageCount, 1) where !sub.removedFlags[i] {
            let newParent = map[Int(sub.parents[i])]
            guard newParent != Self.noParent else { continue }
            map[i] = append(name: sub.names[i], parent: newParent, type: sub.types[i],
                            kind: sub.kinds[i], size: sub.sizes[i], modDate: sub.modDates[i])
        }
        for i in 0..<sub.storageCount where map[i] != Self.noParent && sub.types[i] == .directory {
            childLists[Int(map[i])] = sub.childLists[i].map { map[Int($0)] }
        }

        let delta = Int64(sub.sizes[0]) - Int64(sizes[n])
        sizes[n] = sub.sizes[0]
        kinds[n] = sub.kinds[0]
        unreadablePaths.removeAll { $0 == nodePath || $0.hasPrefix(nodePath + "/") }
        unreadablePaths.append(contentsOf: sub.unreadablePaths)
        unreadablePaths.sort()
        if let p = parent(of: node) {
            sortChildren(of: p)
            adjustAncestors(startingAt: p, delta: delta)
        }
    }

    // MARK: - Interne

    private mutating func markRemoved(_ node: NodeID) {
        var stack = [node]
        while let cur = stack.popLast() {
            let i = Int(cur)
            removedFlags[i] = true
            names[i] = ""
            stack.append(contentsOf: childLists[i])
            childLists[i] = []
        }
    }

    private mutating func adjustAncestors(startingAt start: NodeID, delta: Int64) {
        var cur = start
        while cur != Self.noParent {
            let i = Int(cur)
            sizes[i] = UInt64(max(0, Int64(sizes[i]) + delta))
            kinds[i] = dominantKind(of: cur)
            let up = parents[i]
            if up != Self.noParent { sortChildren(of: up) }
            cur = up
        }
    }

    private mutating func sortChildren(of node: NodeID) {
        let s = sizes
        let n = names
        var list = childLists[Int(node)]
        list.sort { a, b in
            let sa = s[Int(a)], sb = s[Int(b)]
            return sa != sb ? sa > sb : n[Int(a)] < n[Int(b)]
        }
        childLists[Int(node)] = list
    }

    /// Type dont les enfants directs pèsent le plus (pondéré par la taille).
    private func dominantKind(of node: NodeID) -> ContentKind {
        var totals = [UInt64](repeating: 0, count: ContentKind.allCases.count)
        for c in childLists[Int(node)] { totals[Int(kinds[Int(c)].rawValue)] += sizes[Int(c)] }
        guard let best = totals.indices.max(by: { totals[$0] < totals[$1] }), totals[best] > 0 else { return .other }
        return ContentKind(rawValue: UInt8(best)) ?? .other
    }
}
