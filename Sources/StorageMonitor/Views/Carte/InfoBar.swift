import AppKit
import StorageCore
import SwiftUI

/// Barre du bas : élément sélectionné et actions.
struct InfoBar: View {
    let model: AppModel
    let tree: FileTree
    @Binding var quickLookURL: URL?

    var body: some View {
        HStack(spacing: 10) {
            if let id = model.selectedNode, !tree.isRemoved(id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: tree.path(of: id)))
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tree.name(of: id)).font(.callout.bold()).lineLimit(1)
                    Text(tree.path(of: id)).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(Format.bytes(tree.size(of: id))).font(.callout.monospacedDigit())
                Button("Afficher dans le Finder") { model.revealInFinder(id) }
                Button("Coup d'œil") { quickLookURL = model.url(of: id) }
            } else {
                Text("Clic : sélectionner · double-clic : entrer dans un dossier · ⌘↑ : remonter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }
}
