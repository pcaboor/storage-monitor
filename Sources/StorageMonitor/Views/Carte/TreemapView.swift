import StorageCore
import SwiftUI

/// Dessin interactif du treemap du dossier courant.
struct TreemapView: View {
    let model: AppModel
    let tree: FileTree
    @Binding var quickLookURL: URL?

    @State private var items: [TreemapItem] = []
    @State private var hoverPoint: CGPoint?

    private struct SceneKey: Equatable {
        var node: NodeID
        var version: Int
        var size: CGSize
        var systemOther: UInt64
    }

    var body: some View {
        GeometryReader { geo in
            let key = SceneKey(node: model.currentNode, version: model.treeVersion,
                               size: geo.size, systemOther: model.systemOtherSize)
            let hovered = hoverPoint.flatMap { TreemapScene.hitTest($0, in: items) }

            Canvas { context, _ in
                draw(in: context, hovered: hovered)
            }
            .onChange(of: key, initial: true) {
                items = TreemapScene.build(tree: tree, node: key.node,
                                           in: CGRect(origin: .zero, size: key.size),
                                           systemOtherSize: key.systemOther)
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point): hoverPoint = point
                case .ended: hoverPoint = nil
                }
            }
            .onTapGesture(count: 2) { location in
                guard let item = TreemapScene.hitTest(location, in: items) else { return }
                open(item)
            }
            .onTapGesture(count: 1) { location in
                model.selectedNode = TreemapScene.hitTest(location, in: items)?.node
            }
            .contextMenu {
                if let id = hovered?.node {
                    Button("Afficher dans le Finder") { model.revealInFinder(id) }
                    Button("Coup d'œil") { quickLookURL = model.url(of: id) }
                    Button("Copier le chemin") { model.copyPath(id) }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hovered, let point = hoverPoint {
                    tooltip(for: hovered)
                        .offset(x: min(point.x + 14, max(0, geo.size.width - 240)),
                                y: min(point.y + 14, max(0, geo.size.height - 80)))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Double-clic : entrer dans un dossier, sinon Coup d'œil.
    private func open(_ item: TreemapItem) {
        guard let id = item.node else { return }
        if tree.nodeType(of: id) == .directory {
            model.navigate(to: id)
        } else {
            model.selectedNode = id
            quickLookURL = model.url(of: id)
        }
    }

    private func draw(in context: GraphicsContext, hovered: TreemapItem?) {
        for item in items {
            let rect = item.rect.insetBy(dx: 0.5, dy: 0.5)
            guard rect.width >= 1, rect.height >= 1 else { continue }
            let shape = Path(roundedRect: rect, cornerRadius: 2)
            let isContainer = item.depth == 0 && item.node.map { tree.nodeType(of: $0) == .directory } == true
            var color = item.kind.color
            if case .smallItems = item.content { color = color.opacity(0.5) }
            if isContainer { color = color.opacity(0.55) }
            context.fill(shape, with: .color(color))
            context.stroke(shape, with: .color(.black.opacity(0.3)), lineWidth: 0.5)

            if rect.width > 36, rect.height > 14 {
                let text = Text(item.label)
                    .font(.system(size: 10, weight: item.depth == 0 ? .semibold : .regular))
                    .foregroundStyle(.black.opacity(0.8))
                context.draw(text, in: CGRect(x: rect.minX + 4, y: rect.minY + 2,
                                              width: rect.width - 8, height: 13))
            }
        }

        if let hovered {
            context.fill(Path(roundedRect: hovered.rect, cornerRadius: 2), with: .color(.white.opacity(0.18)))
        }
        if let selected = model.selectedNode, let item = items.last(where: { $0.node == selected }) {
            let path = Path(roundedRect: item.rect.insetBy(dx: 1, dy: 1), cornerRadius: 2)
            context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 3)
            context.stroke(path, with: .color(.white), lineWidth: 1.5)
        }
    }

    private func tooltip(for item: TreemapItem) -> some View {
        let parentSize = item.node.flatMap { tree.parent(of: $0) }.map { tree.size(of: $0) }
            ?? tree.size(of: model.currentNode)
        return VStack(alignment: .leading, spacing: 2) {
            Text(item.label).font(.callout.bold()).lineLimit(1)
            Text("\(Format.bytes(item.size)) · \(Format.percent(item.size, of: parentSize)) du dossier")
                .font(.caption)
            if let id = item.node {
                Text("Modifié le \(tree.modificationDate(of: id).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: 230, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
