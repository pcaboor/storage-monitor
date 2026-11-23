/// Reconnaît les dossiers que le Finder présente comme un seul fichier (paquets).
enum PackageDetector {
    static let packageExtensions: Set<String> = [
        "app", "appex", "framework", "bundle", "plugin", "kext", "prefpane", "qlgenerator",
        "mdimporter", "saver", "xpc", "wdgt",
        "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary", "musiclibrary",
        "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band", "lrlibrary",
        "xcodeproj", "xcworkspace", "playground", "xcarchive", "dsym", "docarchive",
        "pages", "numbers", "key", "rtfd",
        "sparsebundle", "pvm", "vmwarevm", "utm", "pkg", "mpkg",
    ]

    static func isPackage(name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return packageExtensions.contains(name[name.index(after: dot)...].lowercased())
    }
}
