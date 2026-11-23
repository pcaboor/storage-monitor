import StorageCore
import SwiftUI

/// Écran « Carte », version provisoire : résumé du scan. Le treemap arrive à la tâche 11.
struct CarteView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            if let tree = model.tree {
                Text("\(tree.liveNodeCount.formatted()) éléments · \(Format.bytes(tree.totalSize))")
                    .font(.title2.monospacedDigit())
                Text(Format.scanDate(tree.scanDate))
                    .foregroundStyle(.secondary)
            } else if !model.isScanning {
                ContentUnavailableView {
                    Label("Aucun scan", systemImage: "internaldrive")
                } description: {
                    Text("Lance un premier scan pour cartographier ton disque.")
                } actions: {
                    Button("Scanner le disque") { model.startFullScan() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if case let .scanning(progress) = model.scanState {
                ScanProgressView(progress: progress) { model.cancelScan() }
            }
        }
        .alert("Le scan a échoué", isPresented: errorBinding) {
            Button("OK") { model.dismissError() }
        } message: {
            if case let .failed(message) = model.scanState { Text(message) }
        }
        .navigationTitle("Carte")
        .toolbar {
            Button { model.startFullScan() } label: { Label("Rescanner tout", systemImage: "arrow.clockwise") }
                .help("Rescanner tout")
                .disabled(model.isScanning)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = model.scanState { true } else { false } },
            set: { if !$0 { model.dismissError() } }
        )
    }
}
