import AppKit
import Foundation
import Observation
import StorageCore

enum SidebarItem: Hashable {
    case carte
}

/// État global de l'app : dernier scan, navigation dans la carte, autorisations.
@MainActor
@Observable
final class AppModel {
    enum ScanState: Equatable {
        case idle
        case scanning(ScanProgress)
        case failed(String)
    }

    private(set) var tree: FileTree?
    /// Incrémenté à chaque changement de `tree`, pour invalider les caches des vues.
    private(set) var treeVersion = 0
    private(set) var scanState: ScanState = .idle
    private(set) var volume: VolumeInfo?
    private(set) var hasFullDiskAccess = true
    var continueWithoutAccess = false
    var sidebarSelection: SidebarItem? = .carte
    private(set) var currentNode: NodeID = 0
    var selectedNode: NodeID?

    private let store: ScanStore
    private let scanner: DiskScanner
    private var scanTask: Task<Void, Never>?

    init(store: ScanStore = ScanStore(), scanner: DiskScanner = DiskScanner()) {
        self.store = store
        self.scanner = scanner
    }

    var needsAccessOnboarding: Bool { !hasFullDiskAccess && !continueWithoutAccess }

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    var canGoUp: Bool { tree?.parent(of: currentNode) != nil }

    /// Bloc « Système et autres », affiché uniquement à la racine d'un scan de `/`.
    var systemOtherSize: UInt64 {
        guard let tree, let volume, tree.rootPath == "/", currentNode == tree.root else { return 0 }
        return VolumeInfo.systemOtherSize(used: volume.usedCapacity, scanned: tree.totalSize)
    }

    // MARK: - Cycle de vie

    func start() async {
        recheckAccess()
        refreshVolume()
        let store = self.store
        let loaded = await Task.detached(priority: .userInitiated) { try? store.load() }.value
        if tree == nil, let loaded {
            tree = loaded
            currentNode = loaded.root
            treeVersion += 1
        }
    }

    func recheckAccess() {
        hasFullDiskAccess = FullDiskAccess.isGranted()
    }

    func refreshVolume() {
        volume = try? VolumeInfo.current(for: "/")
    }

    // MARK: - Scan

    func startFullScan() {
        startScan(root: "/", replacing: nil)
    }

    func refreshCurrentFolder() {
        guard let tree else { return }
        if currentNode == tree.root {
            startScan(root: tree.rootPath, replacing: nil)
        } else {
            startScan(root: tree.path(of: currentNode), replacing: currentNode)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func dismissError() {
        if case .failed = scanState { scanState = .idle }
    }

    private func startScan(root: String, replacing node: NodeID?) {
        guard !isScanning else { return }
        scanState = .scanning(ScanProgress(currentPath: root))
        let scanner = self.scanner
        scanTask = Task {
            do {
                let result = try await scanner.scan(root: root) { [weak self] progress in
                    Task { @MainActor in self?.updateProgress(progress) }
                }
                finishScan(result, replacing: node)
            } catch is CancellationError {
                scanState = .idle
            } catch let ScanError.rootUnreadable(path, code) {
                scanState = .failed("Impossible de lire \(path) : \(String(cString: strerror(code))).")
            } catch {
                scanState = .failed(error.localizedDescription)
            }
        }
    }

    private func updateProgress(_ progress: ScanProgress) {
        if case .scanning = scanState { scanState = .scanning(progress) }
    }

    private func finishScan(_ result: FileTree, replacing node: NodeID?) {
        if let node, tree != nil {
            tree?.replaceSubtree(at: node, with: result) // mutation en place, sans copie
        } else {
            tree = result
            currentNode = result.root
            selectedNode = nil
        }
        treeVersion += 1
        scanState = .idle
        refreshVolume()
        if let snapshot = tree {
            let store = self.store
            Task.detached(priority: .utility) { try? store.save(snapshot) }
        }
    }

    // MARK: - Navigation

    func navigate(to node: NodeID) {
        guard let tree, !tree.isRemoved(node), tree.nodeType(of: node) == .directory else { return }
        currentNode = node
        selectedNode = nil
    }

    func goUp() {
        guard let tree, let parent = tree.parent(of: currentNode) else { return }
        let previous = currentNode
        currentNode = parent
        selectedNode = previous
    }

    func displayName(of node: NodeID) -> String {
        guard let tree else { return "" }
        if node == tree.root {
            return tree.rootPath == "/" ? (volume?.name ?? "Macintosh HD") : (tree.rootPath as NSString).lastPathComponent
        }
        return tree.name(of: node)
    }

    func url(of node: NodeID) -> URL? {
        guard let tree else { return nil }
        return URL(fileURLWithPath: tree.path(of: node))
    }

    // MARK: - Actions Finder

    func revealInFinder(_ node: NodeID) {
        guard let url = url(of: node) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ node: NodeID) {
        guard let tree else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tree.path(of: node), forType: .string)
    }
}
