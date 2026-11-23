import Foundation

public struct ScanProgress: Sendable, Equatable {
    public var entryCount: Int
    public var byteCount: UInt64
    public var currentPath: String

    public init(entryCount: Int = 0, byteCount: UInt64 = 0, currentPath: String = "") {
        self.entryCount = entryCount
        self.byteCount = byteCount
        self.currentPath = currentPath
    }
}

public enum ScanError: Error, Equatable {
    case rootUnreadable(path: String, errno: Int32)
}

/// Parcourt un dossier en parallèle et construit un `FileTree`.
public struct DiskScanner: Sendable {
    /// Chemins jamais parcourus : volume Data déjà visible via les firmlinks, disques externes, pseudo-systèmes.
    public static let defaultExcludedPaths: Set<String> = [
        "/System/Volumes", "/Volumes", "/dev", "/Network", "/net", "/home",
    ]

    public var excludedPaths: Set<String>
    public var maxConcurrency: Int

    public init(excludedPaths: Set<String> = DiskScanner.defaultExcludedPaths,
                maxConcurrency: Int = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount - 1))) {
        self.excludedPaths = excludedPaths
        self.maxConcurrency = maxConcurrency
    }

    public func scan(root: String, progress: @Sendable (ScanProgress) -> Void = { _ in }) async throws -> FileTree {
        try Task.checkCancellation()

        var devices = Set<Int32>()
        for path in [root, "/", "/System/Volumes/Data"] {
            if let device = Self.deviceID(of: path) { devices.insert(device) }
        }
        let allowedDevices = devices
        let excluded = excludedPaths
        let concurrency = max(1, maxConcurrency)

        var tree = FileTree(rootPath: root)
        var pending: [Job] = [.list(path: root, node: tree.root)]
        var seenHardLinks = Set<HardLinkKey>()
        var unreadable: [String] = []
        var stats = ScanProgress(currentPath: root)
        let clock = ContinuousClock()
        var lastReport = clock.now

        try await withThrowingTaskGroup(of: JobResult.self) { group in
            var running = 0
            while true {
                while running < concurrency, let job = pending.popLast() {
                    group.addTask { Self.perform(job, allowedDevices: allowedDevices) }
                    running += 1
                }
                guard running > 0, let result = try await group.next() else { break }
                running -= 1
                try Task.checkCancellation()

                switch result {
                case .skipped:
                    break
                case let .unreadable(path, code):
                    if path == root { throw ScanError.rootUnreadable(path: root, errno: code) }
                    unreadable.append(path)
                case let .packageSized(node, size):
                    tree.setSize(size, of: node)
                    stats.byteCount += size
                case let .listed(path, node, device, entries):
                    stats.currentPath = path
                    stats.entryCount += entries.count
                    for entry in entries {
                        let childPath = path == "/" ? "/" + entry.name : path + "/" + entry.name
                        switch entry.kind {
                        case .directory:
                            if excluded.contains(childPath) { continue }
                            if PackageDetector.isPackage(name: entry.name) {
                                let id = tree.append(name: entry.name, parent: node, type: .package,
                                                     kind: ContentKind.classify(fileName: entry.name),
                                                     size: 0, modDate: entry.modificationTime)
                                pending.append(.sumPackage(path: childPath, node: id))
                            } else {
                                let id = tree.append(name: entry.name, parent: node, type: .directory,
                                                     kind: .other, size: 0, modDate: entry.modificationTime)
                                pending.append(.list(path: childPath, node: id))
                            }
                        case .file:
                            var size = entry.allocatedSize
                            if entry.linkCount > 1,
                               !seenHardLinks.insert(HardLinkKey(device: device, fileID: entry.fileID)).inserted {
                                size = 0
                            }
                            tree.append(name: entry.name, parent: node, type: .file,
                                        kind: ContentKind.classify(fileName: entry.name),
                                        size: size, modDate: entry.modificationTime)
                            stats.byteCount += size
                        case .symlink, .other:
                            continue
                        }
                    }
                }

                if clock.now - lastReport >= .milliseconds(100) {
                    progress(stats)
                    lastReport = clock.now
                }
            }
        }

        progress(stats)
        tree.unreadablePaths = unreadable.sorted()
        tree.finalize()
        return tree
    }

    // MARK: - Travail parallèle

    private enum Job: Sendable {
        case list(path: String, node: NodeID)
        case sumPackage(path: String, node: NodeID)
    }

    private enum JobResult: Sendable {
        case listed(path: String, node: NodeID, device: Int32, entries: [RawEntry])
        case unreadable(path: String, errno: Int32)
        case skipped
        case packageSized(node: NodeID, size: UInt64)
    }

    private struct HardLinkKey: Hashable, Sendable {
        var device: Int32
        var fileID: UInt64
    }

    private static func perform(_ job: Job, allowedDevices: Set<Int32>) -> JobResult {
        switch job {
        case let .list(path, node):
            do {
                let listing = try DirectoryReader.read(path: path)
                guard allowedDevices.contains(listing.device) else { return .skipped }
                return .listed(path: path, node: node, device: listing.device, entries: listing.entries)
            } catch DirectoryReadError.posix(let code) {
                return .unreadable(path: path, errno: code)
            } catch {
                return .unreadable(path: path, errno: EIO)
            }
        case let .sumPackage(path, node):
            return .packageSized(node: node, size: packageSize(at: path))
        }
    }

    /// Taille totale d'un paquet (contenu récursif, liens physiques comptés une fois).
    static func packageSize(at path: String) -> UInt64 {
        var total: UInt64 = 0
        var seen = Set<UInt64>()
        var stack = [path]
        while let dir = stack.popLast() {
            guard let listing = try? DirectoryReader.read(path: dir) else { continue }
            for entry in listing.entries {
                switch entry.kind {
                case .directory:
                    stack.append(dir + "/" + entry.name)
                case .file:
                    if entry.linkCount > 1, !seen.insert(entry.fileID).inserted { continue }
                    total += entry.allocatedSize
                case .symlink, .other:
                    continue
                }
            }
        }
        return total
    }

    static func deviceID(of path: String) -> Int32? {
        var info = stat()
        return stat(path, &info) == 0 ? info.st_dev : nil
    }
}
