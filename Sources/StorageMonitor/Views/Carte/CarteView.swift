import AppKit
import QuickLook
import StorageCore
import SwiftUI

/// Écran « Carte » : fil d'Ariane, treemap, légende et barre d'infos.
struct CarteView: View {
    let model: AppModel

    @State private var quickLookURL: URL?
    @State private var showUnreadable = false

    var body: some View {
        VStack(spacing: 0) {
            if let tree = model.tree {
                header(tree)
                if !model.hasFullDiskAccess {
                    HStack(spacing: 8) {
                        Label("Scan partiel : l'Accès complet au disque n'est pas accordé.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Autoriser l'accès…") { model.continueWithoutAccess = false }
                            .buttonStyle(.link)
                    }
                    .font(.caption)
                    .padding(.bottom, 4)
                }
                TreemapView(model: model, tree: tree, quickLookURL: $quickLookURL)
                    .padding(.horizontal, 8)
                LegendView()
                    .padding(.vertical, 6)
                Divider()
                InfoBar(model: model, tree: tree, quickLookURL: $quickLookURL)
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
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let id = model.selectedNode else { return .ignored }
            quickLookURL = model.url(of: id)
            return .handled
        }
        .quickLookPreview($quickLookURL)
        .alert("Le scan a échoué", isPresented: errorBinding) {
            Button("OK") { model.dismissError() }
        } message: {
            if case let .failed(message) = model.scanState { Text(message) }
        }
        .navigationTitle("Carte")
        .toolbar {
            ToolbarItemGroup {
                Button { model.goUp() } label: { Label("Remonter", systemImage: "chevron.up") }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!model.canGoUp)
                Button { model.refreshCurrentFolder() } label: {
                    Label("Rafraîchir ce dossier", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Rafraîchir ce dossier")
                .disabled(model.tree == nil || model.isScanning)
                Button { model.startFullScan() } label: { Label("Rescanner tout", systemImage: "arrow.clockwise") }
                    .help("Rescanner tout")
                    .disabled(model.isScanning)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = model.scanState { true } else { false } },
            set: { if !$0 { model.dismissError() } }
        )
    }

    private func header(_ tree: FileTree) -> some View {
        HStack(spacing: 12) {
            BreadcrumbView(model: model, tree: tree)
            Spacer()
            if !tree.unreadablePaths.isEmpty {
                Button("\(tree.unreadablePaths.count) dossiers inaccessibles") { showUnreadable = true }
                    .buttonStyle(.link)
                    .font(.caption)
                    .popover(isPresented: $showUnreadable) {
                        List(tree.unreadablePaths, id: \.self) { Text($0).font(.caption.monospaced()) }
                            .frame(width: 520, height: 320)
                    }
            }
            Text(Format.scanDate(tree.scanDate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
