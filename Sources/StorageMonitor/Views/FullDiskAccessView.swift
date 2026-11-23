import AppKit
import StorageCore
import SwiftUI

/// Écran d'accueil affiché tant que l'« Accès complet au disque » n'est pas accordé.
struct FullDiskAccessView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Accès complet au disque")
                .font(.title.bold())
            Text("""
            Pour cartographier tout ton Mac, Storage Monitor doit pouvoir lire tous les dossiers, \
            y compris ceux que macOS protège (Mail, Safari, conteneurs d'apps…).

            Ouvre Réglages Système › Confidentialité et sécurité › Accès complet au disque, \
            active « Storage Monitor », puis reviens ici.
            """)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 500)

            HStack(spacing: 12) {
                Button("Ouvrir les Réglages") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                    .buttonStyle(.borderedProminent)
                Button("Vérifier à nouveau") { model.recheckAccess() }
                Button("Continuer sans") { model.continueWithoutAccess = true }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
