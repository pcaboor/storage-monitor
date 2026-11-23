import Foundation

/// Dossier temporaire propre à un test, supprimé à la fin.
final class TempDir {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let url = base.appendingPathComponent("sm-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = url.path
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Crée un fichier de `bytes` octets (dossiers intermédiaires compris) et renvoie son chemin.
    @discardableResult
    func file(_ relative: String, bytes: Int) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: URL(fileURLWithPath: full))
        return full
    }

    @discardableResult
    func dir(_ relative: String) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }
}

/// Taille allouée sur le disque, d'après `lstat`.
func allocatedSize(_ path: String) -> UInt64 {
    var info = stat()
    guard lstat(path, &info) == 0 else { return 0 }
    return UInt64(info.st_blocks) * 512
}

/// Boîte thread-safe pour récupérer des valeurs depuis des closures `@Sendable`.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

/// Identifiant du volume qui contient le chemin.
func deviceID(_ path: String) -> Int32 {
    var info = stat()
    _ = stat(path, &info)
    return info.st_dev
}
