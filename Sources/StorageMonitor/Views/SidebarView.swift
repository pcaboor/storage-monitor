import StorageCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Label("Carte", systemImage: "square.grid.3x3.fill")
                .tag(SidebarItem.carte)
        }
        .safeAreaInset(edge: .bottom) {
            DiskGaugeView(volume: model.volume)
                .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }
}

/// Jauge « Libre : X sur Y » en bas de la barre latérale.
struct DiskGaugeView: View {
    let volume: VolumeInfo?

    var body: some View {
        if let volume {
            let free = volume.availableForImportantUsage
            let total = max(volume.totalCapacity, 1)
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(total - min(free, total)), total: Double(total))
                Text("Libre : \(Format.bytes(free)) sur \(Format.bytes(volume.totalCapacity))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
