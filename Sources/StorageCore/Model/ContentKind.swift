/// Type de contenu d'un nœud, utilisé pour la couleur du treemap.
public enum ContentKind: UInt8, CaseIterable, Sendable {
    case video, image, audio, code, app, archive, document, system, other

    /// Libellé français affiché dans la légende.
    public var label: String {
        switch self {
        case .video: "Vidéos"
        case .image: "Images"
        case .audio: "Audio"
        case .code: "Code"
        case .app: "Applications"
        case .archive: "Archives"
        case .document: "Documents"
        case .system: "Système"
        case .other: "Autres"
        }
    }

    /// Classe un fichier (ou un paquet) d'après son extension.
    public static func classify(fileName: String) -> ContentKind {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return .other }
        let ext = fileName[fileName.index(after: dot)...].lowercased()
        return byExtension[ext] ?? .other
    }

    private static let byExtension: [String: ContentKind] = {
        var map: [String: ContentKind] = [:]
        func add(_ kind: ContentKind, _ exts: [String]) { for e in exts { map[e] = kind } }
        add(.video, ["mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg", "3gp", "fcpbundle", "imovielibrary", "tvlibrary"])
        add(.image, ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp", "cr2", "cr3", "nef", "arw", "dng", "psd", "svg", "ico", "icns", "photoslibrary", "photolibrary"])
        add(.audio, ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "caf", "musiclibrary", "logicx", "band"])
        add(.code, ["swift", "js", "mjs", "cjs", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "c", "h", "cpp", "hpp", "m", "mm", "java", "kt", "php", "cs", "sh", "json", "yaml", "yml", "toml", "css", "scss", "html", "map", "wasm", "xcodeproj", "xcworkspace", "playground"])
        add(.app, ["app", "appex", "framework", "bundle", "plugin", "prefpane", "qlgenerator", "mdimporter", "saver", "xpc"])
        add(.archive, ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "pkg", "xip", "iso", "img", "sparsebundle", "sparseimage", "jar", "whl"])
        add(.document, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "md", "rtf", "rtfd", "csv", "epub", "odt", "ods"])
        add(.system, ["dylib", "so", "kext", "plist", "dsym", "car", "nib", "strings", "log", "db", "sqlite", "sqlite-wal", "sqlite-shm", "raw", "vmdk", "qcow2", "dat", "cache"])
        return map
    }()
}

/// Nature d'un nœud de l'arbre.
public enum NodeType: UInt8, Sendable {
    case file = 0
    /// Dossier explorable.
    case directory = 1
    /// Paquet (`.app`, `.photoslibrary`…) : une feuille dont la taille couvre tout le contenu.
    case package = 2
}
