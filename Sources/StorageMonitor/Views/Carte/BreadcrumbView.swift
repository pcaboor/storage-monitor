import StorageCore
import SwiftUI

/// Fil d'Ariane cliquable, de la racine du scan jusqu'au dossier affiché.
struct BreadcrumbView: View {
    let model: AppModel
    let tree: FileTree

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tree.ancestors(of: model.currentNode).enumerated()), id: \.element) { index, id in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                Button(model.displayName(of: id)) { model.navigate(to: id) }
                    .buttonStyle(.plain)
                    .fontWeight(id == model.currentNode ? .semibold : .regular)
                    .lineLimit(1)
            }
        }
    }
}
