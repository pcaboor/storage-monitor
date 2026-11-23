import Foundation

/// Détecte si l'app dispose de l'« Accès complet au disque ».
public enum FullDiskAccess {
    /// Dossiers protégés par TCC : illisibles (EPERM) sans l'autorisation.
    public static var defaultProbePaths: [String] {
        let home = NSHomeDirectory()
        return [
            home + "/Library/Application Support/com.apple.TCC",
            home + "/Library/Safari",
            home + "/Library/Mail",
        ]
    }

    /// Vrai dès qu'un dossier sonde est lisible. Vrai aussi si aucun n'existe (rien ne permet de conclure).
    public static func isGranted(probePaths: [String] = defaultProbePaths) -> Bool {
        var sawDenied = false
        for path in probePaths {
            do {
                _ = try DirectoryReader.read(path: path)
                return true
            } catch DirectoryReadError.posix(let code) where code == EPERM || code == EACCES {
                sawDenied = true
            } catch {
                continue
            }
        }
        return !sawDenied
    }

    /// Ouvre directement le bon panneau de Réglages Système.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
