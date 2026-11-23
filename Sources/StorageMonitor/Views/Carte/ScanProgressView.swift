import StorageCore
import SwiftUI

/// Panneau affiché pendant un scan, avec le bouton Annuler.
struct ScanProgressView: View {
    let progress: ScanProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large)
            Text("Analyse du disque…").font(.headline)
            Text("\(progress.entryCount.formatted()) éléments · \(Format.bytes(progress.byteCount))")
                .font(.callout.monospacedDigit())
            Text(progress.currentPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 420)
            Button("Annuler", role: .cancel, action: onCancel)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
