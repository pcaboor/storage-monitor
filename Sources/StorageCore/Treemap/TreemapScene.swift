import CoreGraphics

/// Un rectangle à dessiner dans le treemap.
public struct TreemapItem: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case node(NodeID)
        /// Regroupement des éléments trop petits pour être dessinés.
        case smallItems(count: Int)
        /// Espace utilisé non couvert par le scan (affiché seulement à la racine).
        case systemOther
    }

    public var content: Content
    public var rect: CGRect
    /// 0 = enfant direct du dossier affiché, 1 = petit-enfant.
    public var depth: Int
    public var kind: ContentKind
    public var size: UInt64
    public var label: String

    public var node: NodeID? {
        if case let .node(id) = content { return id }
        return nil
    }
}

/// Construit la liste des rectangles à dessiner pour un dossier, sur deux niveaux.
public enum TreemapScene {
    /// Aire estimée (en points²) sous laquelle un élément rejoint le bloc « petits éléments ».
    public static let minimumItemArea: CGFloat = 36
    /// Côté minimal d'un dossier pour afficher son contenu (2e niveau).
    public static let minimumNestingSide: CGFloat = 40
    /// Bandeau réservé au nom du dossier au-dessus de son contenu.
    public static let headerHeight: CGFloat = 16
    public static let padding: CGFloat = 2

    public static func build(tree: FileTree, node: NodeID, in rect: CGRect,
                             systemOtherSize: UInt64 = 0) -> [TreemapItem] {
        let top = layoutLevel(tree: tree, children: tree.children(of: node),
                              systemOtherSize: systemOtherSize, depth: 0, in: rect)
        var items = top
        for item in top {
            guard let id = item.node, tree.nodeType(of: id) == .directory,
                  item.rect.width >= minimumNestingSide, item.rect.height >= minimumNestingSide else { continue }
            let inner = CGRect(x: item.rect.minX + padding,
                               y: item.rect.minY + headerHeight,
                               width: item.rect.width - 2 * padding,
                               height: item.rect.height - headerHeight - padding)
            guard inner.width > 0, inner.height > 0 else { continue }
            items += layoutLevel(tree: tree, children: tree.children(of: id),
                                 systemOtherSize: 0, depth: 1, in: inner)
        }
        return items
    }

    /// L'élément le plus profond sous le point, s'il y en a un.
    public static func hitTest(_ point: CGPoint, in items: [TreemapItem]) -> TreemapItem? {
        items.last { $0.rect.contains(point) }
    }

    private struct Entry {
        var content: TreemapItem.Content
        var size: UInt64
        var kind: ContentKind
        var label: String
    }

    private static func layoutLevel(tree: FileTree, children: [NodeID], systemOtherSize: UInt64,
                                    depth: Int, in rect: CGRect) -> [TreemapItem] {
        let childTotal = children.reduce(UInt64(0)) { $0 + tree.size(of: $1) }
        let total = Double(childTotal + systemOtherSize)
        guard total > 0, rect.width > 0, rect.height > 0 else { return [] }
        let areaPerByte = Double(rect.width * rect.height) / total

        var entries: [Entry] = []
        var smallCount = 0
        var smallSize: UInt64 = 0
        for child in children { // déjà triés par taille décroissante
            let size = tree.size(of: child)
            guard size > 0 else { continue }
            if smallCount > 0 || Double(size) * areaPerByte < Double(minimumItemArea) {
                smallCount += 1
                smallSize += size
            } else {
                entries.append(Entry(content: .node(child), size: size,
                                     kind: tree.kind(of: child), label: tree.name(of: child)))
            }
        }
        if systemOtherSize > 0 {
            entries.append(Entry(content: .systemOther, size: systemOtherSize, kind: .system, label: "Système et autres"))
        }
        if smallCount > 0 {
            let label = smallCount == 1 ? "1 petit élément" : "\(smallCount) petits éléments"
            entries.append(Entry(content: .smallItems(count: smallCount), size: smallSize, kind: .other, label: label))
        }
        entries.sort { $0.size > $1.size }

        let rects = TreemapLayout.squarify(sizes: entries.map { Double($0.size) }, in: rect)
        return zip(entries, rects).map { entry, r in
            TreemapItem(content: entry.content, rect: r, depth: depth,
                        kind: entry.kind, size: entry.size, label: entry.label)
        }
    }
}
