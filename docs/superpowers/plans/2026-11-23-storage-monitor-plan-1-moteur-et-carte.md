# Storage Monitor : plan d'implémentation 1/2 (moteur et carte)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Objectif :** une app macOS native qui scanne tout le disque et affiche une carte (treemap) navigable de l'espace occupé, avec l'écran d'accès au disque, la persistance du dernier scan et un build signé. C'est l'équivalent de DaisyDisk. Les suggestions, le panier et le nettoyage feront l'objet du plan 2/2.

**Architecture :** un paquet SwiftPM avec deux cibles.
- `StorageCore` est une bibliothèque sans interface, entièrement testée. Elle contient le scanner parallèle fondé sur `getattrlistbulk`, l'arbre compact `FileTree`, l'algorithme du treemap, la persistance binaire, ainsi que les infos du volume et le test d'accès au disque.
- `StorageMonitor` est l'exécutable SwiftUI : un `AppModel` `@Observable` sur le `MainActor` et des vues fines.
- Des scripts shell assemblent et signent le bundle `.app`.

**Stack technique :** Swift 6.1 (mode de langage Swift 6, concurrence stricte), SwiftUI et AppKit (macOS 14+), `swift-testing`, SwiftPM sans aucune dépendance externe. Le build se fait avec les **Command Line Tools uniquement** : Xcode n'est pas installé.

**Spec de référence :** `docs/superpowers/specs/2026-11-23-storage-monitor-design.md`, sections 2, 3, 5.1, 5.4, 7 (lignes scan et persistance), 8, 9 et 10. Les sections 4, 5.2, 5.3 et 6 relèvent du plan 2/2.

## Contraintes globales

- `swift-tools-version:6.0`, `platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion` = `14.0`.
- Aucune dépendance SwiftPM externe. Seuls les frameworks Apple du SDK sont autorisés.
- Tests avec `swift-testing` (`import Testing`, `@Test`, `#expect`). **XCTest n'est pas disponible** sans Xcode.
- Identifiant de bundle : `local.storage-monitor`. Nom affiché : `Storage Monitor`. Exécutable : `StorageMonitor`.
- Identité de signature : `Storage Monitor Local`.
- Données de l'app : `~/Library/Application Support/StorageMonitor/`, fichier `last-scan.bin`.
- Interface **en français**, en tutoyant l'utilisateur.
- Tailles toujours mesurées en **taille allouée sur le disque**, jamais en taille logique.
- Ne jamais nommer un type `Scanner` : ce nom entre en conflit avec `Foundation.Scanner`. Le scanner s'appelle `DiskScanner`.
- Dossiers exclus du scan : `/System/Volumes`, `/Volumes`, `/dev`, `/Network`, `/net`, `/home`. Seuls les volumes de `/`, `/System/Volumes/Data` et de la racine scannée sont parcourus.

## Notes d'exécution (à lire avant de commencer)

- **Limite de temps sur les tests.** Lance toujours les tests avec une limite, par exemple `perl -e 'alarm 300; exec @ARGV' swift test`. Un test qui boucle bloquerait sinon la session indéfiniment. Le code exit 142 signifie que la limite a été atteinte.
- **Sortie condensée.** Un hook `rtk` peut résumer la sortie de `swift build` et `swift test` (par exemple « ok (build complete) »). Pour voir la sortie brute, préfixe la commande par `rtk proxy`.
- **Compilation des tests.** `swift test` compile d'abord : la première fois, compte environ 1 minute.
- **Format de `getattrlistbulk`, vérifié sur ce Mac (macOS 26).** Seuls les attributs signalés dans `ATTR_CMN_RETURNED_ATTRS` sont présents dans le tampon, même avec `FSOPT_PACK_INVAL_ATTRS`. Un dossier n'a ni `ATTR_FILE_LINKCOUNT` ni `ATTR_FILE_ALLOCSIZE`, et `ATTR_CMN_ERROR` n'est pas renvoyé quand il vaut zéro. Le décodeur de la tâche 5 lit donc chaque champ selon ce masque. **Ne le « simplifie » pas.**
- **Mesures du prototype** (scan de `/` sur ce Mac) : 3 048 505 entrées en 40 s ; 240 Mo de RAM pour 2,5 millions d'entrées ; sauvegarde 7,5 s, chargement 0,3 s, fichier de 28 Mo. Le total scanné plus « Système et autres » correspond exactement à l'espace utilisé du volume.
- **Interface.** Les tâches 9 à 11 n'ont pas de tests automatisés (spec section 9) : on les vérifie en lançant l'app, avec les listes de contrôle fournies.

## Structure des fichiers

```
Package.swift                                    tâche 1, modifié à la tâche 9
Sources/StorageCore/
  Model/ContentKind.swift                        ContentKind (type de contenu) et NodeType          T1
  Model/FileTree.swift                           arbre compact, agrégats, mutations                 T2
  Treemap/TreemapLayout.swift                    algorithme squarified (fonction pure)              T3
  Treemap/TreemapScene.swift                     rectangles à dessiner sur 2 niveaux, hit-test      T4
  Scan/PackageDetector.swift                     extensions de paquets (.app…)                      T1
  Scan/DirectoryReader.swift                     lecture d'un dossier via getattrlistbulk           T5
  Scan/DiskScanner.swift                         parcours parallèle → FileTree                      T6
  Persistence/ScanStore.swift                    sauvegarde binaire LZFSE versionnée                T7
  System/VolumeInfo.swift                        capacités du volume, « Système et autres »         T8
  System/FullDiskAccess.swift                    détection de l'Accès complet au disque             T8
Tests/StorageCoreTests/
  TestSupport.swift                              TempDir, allocatedSize, deviceID, LockedBox        T5
  ContentKindTests.swift  FileTreeTests.swift  TreemapLayoutTests.swift  TreemapSceneTests.swift
  DirectoryReaderTests.swift  DiskScannerTests.swift  ScanStoreTests.swift  SystemTests.swift
Sources/StorageMonitor/
  StorageMonitorApp.swift                        @main et AppDelegate                               T9
  AppModel.swift                                 état global (MainActor, @Observable)               T9
  Format.swift                                   octets, dates, pourcentages, couleurs              T9
  Views/RootView.swift                           accès au disque ou NavigationSplitView             T9
  Views/SidebarView.swift                        barre latérale et jauge d'espace libre             T9
  Views/FullDiskAccessView.swift                 écran d'accueil (spec 5.4)                         T9
  Views/Carte/ScanProgressView.swift             progression et bouton Annuler                      T9
  Views/Carte/CarteView.swift                    écran Carte (provisoire en T9, final en T11)       T9/T11
  Views/Carte/TreemapView.swift                  Canvas, survol, clics, menu contextuel             T11
  Views/Carte/BreadcrumbView.swift               fil d'Ariane                                       T11
  Views/Carte/LegendView.swift                   légende des couleurs                               T11
  Views/Carte/InfoBar.swift                      barre d'infos de la sélection                      T11
packaging/Info.plist                             T10
scripts/build-app.sh  scripts/setup-signing.sh   T10
README.md                                        T10
```

---

### Tâche 1 : paquet SwiftPM, types de contenu et détection des paquets

**Fichiers :**
- Créer : `Package.swift`
- Créer : `Sources/StorageCore/Model/ContentKind.swift`
- Créer : `Sources/StorageCore/Scan/PackageDetector.swift`
- Test : `Tests/StorageCoreTests/ContentKindTests.swift`

**Interfaces :**
- Utilise : rien.
- Fournit :
  - `public enum ContentKind: UInt8, CaseIterable, Sendable { case video, image, audio, code, app, archive, document, system, other }`, avec `var label: String` (libellé français) et `static func classify(fileName: String) -> ContentKind`.
  - `public enum NodeType: UInt8, Sendable { case file = 0, directory = 1, package = 2 }`.
  - `enum PackageDetector` (interne), avec `static func isPackage(name: String) -> Bool`.

- [ ] **Étape 1 : créer le paquet**

`Package.swift` :

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StorageMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StorageCore"),
        .testTarget(name: "StorageCoreTests", dependencies: ["StorageCore"]),
    ]
)
```

- [ ] **Étape 2 : écrire le test qui échoue**

`Tests/StorageCoreTests/ContentKindTests.swift` :

```swift
import Testing
@testable import StorageCore

@Suite struct ContentKindTests {
    @Test(arguments: [
        ("film.MP4", ContentKind.video),
        ("photo.heic", .image),
        ("song.flac", .audio),
        ("main.swift", .code),
        ("Safari.app", .app),
        ("backup.tar.gz", .archive),
        ("Installer.dmg", .archive),
        ("rapport.pdf", .document),
        ("Docker.raw", .system),
        ("Makefile", .other),
        (".zshrc", .other),
    ])
    func classifiesByExtension(name: String, expected: ContentKind) {
        #expect(ContentKind.classify(fileName: name) == expected)
    }

    @Test func everyKindHasAFrenchLabel() {
        for kind in ContentKind.allCases { #expect(!kind.label.isEmpty) }
        #expect(ContentKind.video.label == "Vidéos")
    }

    @Test func detectsPackagesByExtension() {
        #expect(PackageDetector.isPackage(name: "Safari.app"))
        #expect(PackageDetector.isPackage(name: "Photos Library.photoslibrary"))
        #expect(PackageDetector.isPackage(name: "Projet.XCODEPROJ"))
        #expect(!PackageDetector.isPackage(name: "lodash.merge"))
        #expect(!PackageDetector.isPackage(name: ".app"))
        #expect(!PackageDetector.isPackage(name: "Documents"))
    }
}
```

- [ ] **Étape 3 : vérifier que le test échoue**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : la compilation ÉCHOUE avec `cannot find 'ContentKind' in scope`. Le dossier `Sources/StorageCore` est vide, donc SwiftPM peut aussi signaler une cible sans sources : c'est normal à ce stade.

- [ ] **Étape 4 : écrire l'implémentation**

`Sources/StorageCore/Model/ContentKind.swift` :

```swift
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
```

`Sources/StorageCore/Scan/PackageDetector.swift` :

```swift
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
```

Note : l'extension `.raw` est classée en `system` (c'est celle du disque virtuel de Docker, `Docker.raw`), pas en `image`.

- [ ] **Étape 5 : vérifier que les tests passent**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : `✔ Test run with 3 tests passed`.

- [ ] **Étape 6 : commiter**

```bash
git add Package.swift Sources/StorageCore Tests/StorageCoreTests
git commit -m "feat(core): types de contenu et détection des paquets" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 2 : FileTree, l'arbre compact

**Fichiers :**
- Créer : `Sources/StorageCore/Model/FileTree.swift`
- Test : `Tests/StorageCoreTests/FileTreeTests.swift`

**Interfaces :**
- Utilise : `ContentKind` et `NodeType` (tâche 1).
- Fournit, `public struct FileTree: Sendable` :
  - `typealias NodeID = Int32`, `static let noParent: NodeID = -1`.
  - Propriétés : `let rootPath: String`, `var scanDate: Date`, `var unreadablePaths: [String]`, `var root: NodeID` (toujours 0).
  - Construction : `init(rootPath:scanDate:)`, `append(name:parent:type:kind:size:modDate:) -> NodeID` (`@discardableResult`), `setSize(_:of:)`, `finalize()`.
  - Lecture : `storageCount`, `liveNodeCount`, `totalSize`, `name(of:)`, `size(of:)`, `nodeType(of:)`, `kind(of:)`, `isRemoved(_:)`, `children(of:) -> [NodeID]` (triés par taille décroissante), `modificationDate(of:) -> Date`, `parent(of:) -> NodeID?`, `ancestors(of:) -> [NodeID]` (de la racine au nœud), `path(of:) -> String`, `node(atPath:) -> NodeID?`.
  - Mutations : `remove(_ nodes: [NodeID])`, `replaceSubtree(at:with:)`.
  - Interne (pour `ScanStore`, tâche 7) : les tableaux `names`, `parents`, `types`, `kinds`, `sizes`, `modDates` en lecture, et `init(rootPath:scanDate:unreadablePaths:names:parents:types:kinds:sizes:modDates:)` à partir de tableaux en pré-ordre.

Choix de conception (déjà validés) :
- **Invariant** : l'index d'un enfant est toujours supérieur à celui de son parent. `finalize()` peut donc agréger en une seule passe, de l'index le plus grand au plus petit.
- **Nœuds supprimés** : ils restent dans les tableaux, marqués `removed`, avec leur nom vidé pour libérer la mémoire. Ils sont détachés de leur parent.
- **Type dominant d'un dossier** : c'est le type qui pèse le plus parmi ses **enfants directs**, pondérés par leur taille. Cette approximation se recalcule localement après une mutation.

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/StorageCoreTests/FileTreeTests.swift` :

```swift
import Foundation
import Testing
@testable import StorageCore

/// /data
/// ├── videos/          (dossier)
/// │   ├── a.mp4  600
/// │   └── b.mp4  300
/// ├── notes.txt  50
/// └── code/            (dossier)
///     └── main.swift 100
private func sampleTree() -> (tree: FileTree, videos: NodeID, a: NodeID, b: NodeID, notes: NodeID, code: NodeID, main: NodeID) {
    var tree = FileTree(rootPath: "/data")
    let videos = tree.append(name: "videos", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 10)
    let a = tree.append(name: "a.mp4", parent: videos, type: .file, kind: .video, size: 600, modDate: 11)
    let b = tree.append(name: "b.mp4", parent: videos, type: .file, kind: .video, size: 300, modDate: 12)
    let notes = tree.append(name: "notes.txt", parent: tree.root, type: .file, kind: .document, size: 50, modDate: 13)
    let code = tree.append(name: "code", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 14)
    let main = tree.append(name: "main.swift", parent: code, type: .file, kind: .code, size: 100, modDate: 15)
    tree.finalize()
    return (tree, videos, a, b, notes, code, main)
}

@Suite struct FileTreeTests {
    @Test func finalizeAggregatesSizesAndSortsChildren() {
        let s = sampleTree()
        #expect(s.tree.size(of: s.videos) == 900)
        #expect(s.tree.size(of: s.code) == 100)
        #expect(s.tree.totalSize == 1050)
        #expect(s.tree.children(of: s.tree.root) == [s.videos, s.code, s.notes])
        #expect(s.tree.children(of: s.videos) == [s.a, s.b])
    }

    @Test func directoriesTakeTheirDominantKind() {
        let s = sampleTree()
        #expect(s.tree.kind(of: s.videos) == .video)
        #expect(s.tree.kind(of: s.code) == .code)
        #expect(s.tree.kind(of: s.tree.root) == .video)
    }

    @Test func pathsRoundTrip() {
        let s = sampleTree()
        #expect(s.tree.path(of: s.tree.root) == "/data")
        #expect(s.tree.path(of: s.main) == "/data/code/main.swift")
        #expect(s.tree.node(atPath: "/data/code/main.swift") == s.main)
        #expect(s.tree.node(atPath: "/data") == s.tree.root)
        #expect(s.tree.node(atPath: "/data/absent") == nil)
        #expect(s.tree.node(atPath: "/autre/code") == nil)
    }

    @Test func pathsUnderTheFilesystemRoot() {
        var tree = FileTree(rootPath: "/")
        let users = tree.append(name: "Users", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 0)
        let file = tree.append(name: "f.txt", parent: users, type: .file, kind: .document, size: 1, modDate: 0)
        tree.finalize()
        #expect(tree.path(of: file) == "/Users/f.txt")
        #expect(tree.node(atPath: "/Users/f.txt") == file)
        #expect(tree.node(atPath: "/") == tree.root)
    }

    @Test func ancestorsGoFromRootToNode() {
        let s = sampleTree()
        #expect(s.tree.ancestors(of: s.main) == [s.tree.root, s.code, s.main])
        #expect(s.tree.ancestors(of: s.tree.root) == [s.tree.root])
        #expect(s.tree.parent(of: s.tree.root) == nil)
        #expect(s.tree.parent(of: s.a) == s.videos)
    }

    @Test func modificationDateIsExposedAsDate() {
        let s = sampleTree()
        #expect(s.tree.modificationDate(of: s.a) == Date(timeIntervalSince1970: 11))
    }

    @Test func removeUpdatesAncestorsAndDetaches() {
        var s = sampleTree()
        s.tree.remove([s.a])
        #expect(s.tree.isRemoved(s.a))
        #expect(s.tree.size(of: s.videos) == 300)
        #expect(s.tree.totalSize == 450)
        #expect(s.tree.children(of: s.videos) == [s.b])
        // videos (300) dépasse toujours code (100) : l'ordre est recalculé.
        #expect(s.tree.children(of: s.tree.root) == [s.videos, s.code, s.notes])
        #expect(s.tree.liveNodeCount == 6)
    }

    @Test func removingADirectoryRemovesItsDescendants() {
        var s = sampleTree()
        s.tree.remove([s.videos])
        #expect(s.tree.isRemoved(s.videos))
        #expect(s.tree.isRemoved(s.a))
        #expect(s.tree.isRemoved(s.b))
        #expect(s.tree.totalSize == 150)
        #expect(s.tree.children(of: s.tree.root) == [s.code, s.notes])
        #expect(s.tree.kind(of: s.tree.root) == .code)
        // Supprimer deux fois ne change rien.
        s.tree.remove([s.videos, s.a])
        #expect(s.tree.totalSize == 150)
    }

    @Test func removeIgnoresTheRoot() {
        var s = sampleTree()
        s.tree.remove([s.tree.root])
        #expect(!s.tree.isRemoved(s.tree.root))
        #expect(s.tree.totalSize == 1050)
    }

    @Test func replaceSubtreeGraftsAFreshScan() {
        var s = sampleTree()
        s.tree.unreadablePaths = ["/data/code/secret", "/data/other"]

        var fresh = FileTree(rootPath: "/data/code")
        let lib = fresh.append(name: "lib", parent: fresh.root, type: .directory, kind: .other, size: 0, modDate: 20)
        fresh.append(name: "big.swift", parent: lib, type: .file, kind: .code, size: 2000, modDate: 21)
        fresh.append(name: "small.swift", parent: fresh.root, type: .file, kind: .code, size: 10, modDate: 22)
        fresh.unreadablePaths = ["/data/code/new-locked"]
        fresh.finalize()

        s.tree.replaceSubtree(at: s.code, with: fresh)

        #expect(s.tree.isRemoved(s.main))
        #expect(s.tree.size(of: s.code) == 2010)
        #expect(s.tree.totalSize == 2960)
        let big = try! #require(s.tree.node(atPath: "/data/code/lib/big.swift"))
        #expect(s.tree.size(of: big) == 2000)
        #expect(s.tree.children(of: s.tree.root).first == s.code)
        #expect(s.tree.unreadablePaths == ["/data/code/new-locked", "/data/other"])
    }
}
```

- [ ] **Étape 2 : vérifier que le test échoue**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test --filter FileTreeTests`
Résultat attendu : la compilation ÉCHOUE avec `cannot find 'FileTree' in scope`.

- [ ] **Étape 3 : écrire l'implémentation**

`Sources/StorageCore/Model/FileTree.swift` :

```swift
import Foundation

public typealias NodeID = Int32

/// Arbre compact des fichiers et dossiers scannés (tableaux parallèles indexés par `NodeID`).
///
/// Invariant : l'index d'un enfant est toujours strictement supérieur à celui de son parent.
/// Les nœuds supprimés restent dans les tableaux, marqués `removed`, et sont détachés de leur parent.
public struct FileTree: Sendable {
    public static let noParent: NodeID = -1

    public let rootPath: String
    public var scanDate: Date
    public var unreadablePaths: [String]

    private(set) var names: [String]
    private(set) var parents: [NodeID]
    private(set) var types: [NodeType]
    private(set) var kinds: [ContentKind]
    private(set) var sizes: [UInt64]
    private(set) var modDates: [Int64]
    private(set) var childLists: [[NodeID]]
    private(set) var removedFlags: [Bool]

    public var root: NodeID { 0 }

    public init(rootPath: String, scanDate: Date = Date()) {
        self.rootPath = rootPath
        self.scanDate = scanDate
        unreadablePaths = []
        names = [rootPath]
        parents = [Self.noParent]
        types = [.directory]
        kinds = [.other]
        sizes = [0]
        modDates = [0]
        childLists = [[]]
        removedFlags = [false]
    }

    /// Reconstruit un arbre à partir de tableaux en pré-ordre (utilisé par la persistance).
    init(rootPath: String, scanDate: Date, unreadablePaths: [String],
         names: [String], parents: [NodeID], types: [NodeType], kinds: [ContentKind],
         sizes: [UInt64], modDates: [Int64]) {
        self.rootPath = rootPath
        self.scanDate = scanDate
        self.unreadablePaths = unreadablePaths
        self.names = names
        self.parents = parents
        self.types = types
        self.kinds = kinds
        self.sizes = sizes
        self.modDates = modDates
        removedFlags = [Bool](repeating: false, count: names.count)
        var lists = [[NodeID]](repeating: [], count: names.count)
        for i in 1..<max(names.count, 1) { lists[Int(parents[i])].append(NodeID(i)) }
        childLists = lists
    }

    // MARK: - Construction

    @discardableResult
    public mutating func append(name: String, parent: NodeID, type: NodeType, kind: ContentKind,
                                size: UInt64, modDate: Int64) -> NodeID {
        let id = NodeID(names.count)
        names.append(name)
        parents.append(parent)
        types.append(type)
        kinds.append(kind)
        sizes.append(size)
        modDates.append(modDate)
        childLists.append([])
        removedFlags.append(false)
        childLists[Int(parent)].append(id)
        return id
    }

    public mutating func setSize(_ size: UInt64, of node: NodeID) {
        sizes[Int(node)] = size
    }

    /// Calcule la taille cumulée et le type dominant de chaque dossier,
    /// et trie les enfants par taille décroissante. À appeler une fois la construction terminée.
    public mutating func finalize() {
        for i in stride(from: names.count - 1, through: 0, by: -1)
        where types[i] == .directory && !removedFlags[i] {
            var total: UInt64 = 0
            for c in childLists[i] { total += sizes[Int(c)] }
            sizes[i] = total
            sortChildren(of: NodeID(i))
            kinds[i] = dominantKind(of: NodeID(i))
        }
    }

    // MARK: - Lecture

    /// Nombre d'emplacements, nœuds supprimés compris.
    public var storageCount: Int { names.count }
    public var liveNodeCount: Int { removedFlags.lazy.filter { !$0 }.count }
    public var totalSize: UInt64 { sizes[0] }

    public func name(of node: NodeID) -> String { names[Int(node)] }
    public func size(of node: NodeID) -> UInt64 { sizes[Int(node)] }
    public func nodeType(of node: NodeID) -> NodeType { types[Int(node)] }
    public func kind(of node: NodeID) -> ContentKind { kinds[Int(node)] }
    public func isRemoved(_ node: NodeID) -> Bool { removedFlags[Int(node)] }
    public func children(of node: NodeID) -> [NodeID] { childLists[Int(node)] }

    public func modificationDate(of node: NodeID) -> Date {
        Date(timeIntervalSince1970: TimeInterval(modDates[Int(node)]))
    }

    public func parent(of node: NodeID) -> NodeID? {
        let p = parents[Int(node)]
        return p == Self.noParent ? nil : p
    }

    /// Chaîne de la racine jusqu'au nœud inclus.
    public func ancestors(of node: NodeID) -> [NodeID] {
        var chain: [NodeID] = [node]
        var cur = node
        while let p = parent(of: cur) { chain.append(p); cur = p }
        return chain.reversed()
    }

    public func path(of node: NodeID) -> String {
        if node == root { return rootPath }
        var comps: [String] = []
        var cur = node
        while cur != root {
            comps.append(names[Int(cur)])
            cur = parents[Int(cur)]
        }
        let relative = comps.reversed().joined(separator: "/")
        return rootPath == "/" ? "/" + relative : rootPath + "/" + relative
    }

    public func node(atPath path: String) -> NodeID? {
        if path == rootPath { return root }
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        var cur = root
        for comp in path.dropFirst(prefix.count).split(separator: "/") {
            guard let next = childLists[Int(cur)].first(where: { names[Int($0)] == comp }) else { return nil }
            cur = next
        }
        return cur
    }

    // MARK: - Mutations

    /// Retire des nœuds (et leurs descendants) et met à jour les tailles des ancêtres.
    public mutating func remove(_ nodes: [NodeID]) {
        for node in nodes {
            let i = Int(node)
            guard node != root, !removedFlags[i] else { continue }
            let size = sizes[i]
            let parent = parents[i]
            markRemoved(node)
            childLists[Int(parent)].removeAll { $0 == node }
            adjustAncestors(startingAt: parent, delta: -Int64(size))
        }
    }

    /// Remplace le contenu d'un dossier par un sous-arbre fraîchement scanné du même chemin.
    public mutating func replaceSubtree(at node: NodeID, with sub: FileTree) {
        let n = Int(node)
        let nodePath = path(of: node)
        for c in childLists[n] { markRemoved(c) }
        childLists[n] = []

        var map = [NodeID](repeating: Self.noParent, count: sub.storageCount)
        map[0] = node
        for i in 1..<max(sub.storageCount, 1) where !sub.removedFlags[i] {
            let newParent = map[Int(sub.parents[i])]
            guard newParent != Self.noParent else { continue }
            map[i] = append(name: sub.names[i], parent: newParent, type: sub.types[i],
                            kind: sub.kinds[i], size: sub.sizes[i], modDate: sub.modDates[i])
        }
        for i in 0..<sub.storageCount where map[i] != Self.noParent && sub.types[i] == .directory {
            childLists[Int(map[i])] = sub.childLists[i].map { map[Int($0)] }
        }

        let delta = Int64(sub.sizes[0]) - Int64(sizes[n])
        sizes[n] = sub.sizes[0]
        kinds[n] = sub.kinds[0]
        unreadablePaths.removeAll { $0 == nodePath || $0.hasPrefix(nodePath + "/") }
        unreadablePaths.append(contentsOf: sub.unreadablePaths)
        unreadablePaths.sort()
        if let p = parent(of: node) {
            sortChildren(of: p)
            adjustAncestors(startingAt: p, delta: delta)
        }
    }

    // MARK: - Interne

    private mutating func markRemoved(_ node: NodeID) {
        var stack = [node]
        while let cur = stack.popLast() {
            let i = Int(cur)
            removedFlags[i] = true
            names[i] = ""
            stack.append(contentsOf: childLists[i])
            childLists[i] = []
        }
    }

    private mutating func adjustAncestors(startingAt start: NodeID, delta: Int64) {
        var cur = start
        while cur != Self.noParent {
            let i = Int(cur)
            sizes[i] = UInt64(max(0, Int64(sizes[i]) + delta))
            kinds[i] = dominantKind(of: cur)
            let up = parents[i]
            if up != Self.noParent { sortChildren(of: up) }
            cur = up
        }
    }

    private mutating func sortChildren(of node: NodeID) {
        let s = sizes
        let n = names
        var list = childLists[Int(node)]
        list.sort { a, b in
            let sa = s[Int(a)], sb = s[Int(b)]
            return sa != sb ? sa > sb : n[Int(a)] < n[Int(b)]
        }
        childLists[Int(node)] = list
    }

    /// Type dont les enfants directs pèsent le plus (pondéré par la taille).
    private func dominantKind(of node: NodeID) -> ContentKind {
        var totals = [UInt64](repeating: 0, count: ContentKind.allCases.count)
        for c in childLists[Int(node)] { totals[Int(kinds[Int(c)].rawValue)] += sizes[Int(c)] }
        guard let best = totals.indices.max(by: { totals[$0] < totals[$1] }), totals[best] > 0 else { return .other }
        return ContentKind(rawValue: UInt8(best)) ?? .other
    }
}
```

Point d'attention : `sortChildren` copie `sizes` et `names` dans des constantes locales avant de trier. Les lire via `self` à l'intérieur de la closure de tri provoquerait une erreur d'accès exclusif (« overlapping accesses to self »).

- [ ] **Étape 4 : vérifier que les tests passent**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : `✔ Test run with 13 tests passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Sources/StorageCore/Model/FileTree.swift Tests/StorageCoreTests/FileTreeTests.swift
git commit -m "feat(core): FileTree, arbre compact avec agrégats et mutations" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 3 : algorithme du treemap (squarified)

**Fichiers :**
- Créer : `Sources/StorageCore/Treemap/TreemapLayout.swift`
- Test : `Tests/StorageCoreTests/TreemapLayoutTests.swift`

**Interfaces :**
- Utilise : rien (CoreGraphics).
- Fournit : `public enum TreemapLayout`, avec `static func squarify(sizes: [Double], in rect: CGRect) -> [CGRect]`. Il renvoie un rectangle par taille, dans le même ordre. Une taille nulle donne un rectangle vide.

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/StorageCoreTests/TreemapLayoutTests.swift` :

```swift
import CoreGraphics
import Testing
@testable import StorageCore

private func area(_ r: CGRect) -> Double { Double(r.width * r.height) }

@Suite struct TreemapLayoutTests {
    let bounds = CGRect(x: 10, y: 20, width: 600, height: 400)

    @Test func emptyAndZeroInputsGiveEmptyRects() {
        #expect(TreemapLayout.squarify(sizes: [], in: bounds).isEmpty)
        #expect(TreemapLayout.squarify(sizes: [0, 0], in: bounds).allSatisfy { $0.isEmpty })
        #expect(TreemapLayout.squarify(sizes: [5], in: .zero) == [.zero])
    }

    @Test func singleItemFillsTheRect() {
        let rects = TreemapLayout.squarify(sizes: [42], in: bounds)
        #expect(rects.count == 1)
        #expect(abs(area(rects[0]) - area(bounds)) < 0.5)
        #expect(rects[0].minX == bounds.minX && rects[0].minY == bounds.minY)
    }

    static let cases: [[Double]] = [
        [6, 6, 4, 3, 2, 2, 1],
        [1000, 1, 1, 1],
        [50, 30, 20],
        Array(repeating: 1, count: 37),
    ]

    @Test(arguments: TreemapLayoutTests.cases)
    func rectsAreProportionalInsideAndDisjoint(sizes: [Double]) {
        let rects = TreemapLayout.squarify(sizes: sizes, in: bounds)
        let total = sizes.reduce(0, +)
        #expect(rects.count == sizes.count)

        let covered = rects.map(area).reduce(0, +)
        #expect(abs(covered - area(bounds)) / area(bounds) < 0.001)

        for (size, rect) in zip(sizes, rects) {
            let expected = size / total * area(bounds)
            #expect(abs(area(rect) - expected) / expected < 0.01)
            #expect(rect.minX >= bounds.minX - 0.01 && rect.maxX <= bounds.maxX + 0.01)
            #expect(rect.minY >= bounds.minY - 0.01 && rect.maxY <= bounds.maxY + 0.01)
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || area(overlap) < 0.01)
            }
        }
    }

    @Test func equalSizesInASquareGiveSquares() {
        let rects = TreemapLayout.squarify(sizes: [1, 1, 1, 1], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        for r in rects {
            #expect(abs(r.width - 50) < 0.01)
            #expect(abs(r.height - 50) < 0.01)
        }
    }

    @Test func zeroSizesAtTheEndGetEmptyRects() {
        let rects = TreemapLayout.squarify(sizes: [10, 5, 0], in: bounds)
        #expect(rects[2].isEmpty)
        #expect(abs(area(rects[0]) + area(rects[1]) - area(bounds)) < 0.5)
    }
}
```

Note : les cas paramétrés sont déclarés dans `static let cases: [[Double]]` avec un type explicite. Un tableau littéral imbriqué qui mélange entiers et décimaux directement dans `@Test(arguments:)` fait exploser le temps de vérification de types.

- [ ] **Étape 2 : vérifier que le test échoue**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test --filter TreemapLayoutTests`
Résultat attendu : la compilation ÉCHOUE avec `cannot find 'TreemapLayout' in scope`.

- [ ] **Étape 3 : écrire l'implémentation**

`Sources/StorageCore/Treemap/TreemapLayout.swift` :

```swift
import CoreGraphics

/// Algorithme « squarified » (Bruls, Huizing, van Wijk) : découpe un rectangle
/// en sous-rectangles d'aires proportionnelles aux tailles, aussi carrés que possible.
public enum TreemapLayout {
    /// - Parameter sizes: tailles, idéalement triées par ordre décroissant.
    /// - Returns: un rectangle par taille, dans le même ordre. Une taille nulle donne un rectangle vide.
    public static func squarify(sizes: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: sizes.count)
        let total = sizes.reduce(0) { $0 + max(0, $1) }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let areas = sizes.map { max(0, $0) * scale }
        var remaining = rect
        var start = 0

        while start < areas.count {
            if areas[start] <= 0 {
                result[start] = CGRect(origin: remaining.origin, size: .zero)
                start += 1
                continue
            }
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var rowSum = areas[start]
            var rowMin = areas[start]
            var rowMax = areas[start]
            while end < areas.count, areas[end] > 0 {
                let candidate = areas[end]
                let current = worst(sum: rowSum, min: rowMin, max: rowMax, side: side)
                let next = worst(sum: rowSum + candidate, min: min(rowMin, candidate),
                                 max: max(rowMax, candidate), side: side)
                guard next <= current else { break }
                rowSum += candidate
                rowMin = min(rowMin, candidate)
                rowMax = max(rowMax, candidate)
                end += 1
            }
            remaining = place(row: start..<end, areas: areas, sum: rowSum, in: remaining, into: &result)
            start = end
        }
        return result
    }

    /// Pire rapport d'aspect d'une rangée posée le long d'un côté de longueur `side`.
    private static func worst(sum: Double, min: Double, max: Double, side: Double) -> Double {
        let s2 = side * side
        let sum2 = sum * sum
        return Swift.max(s2 * max / sum2, sum2 / (s2 * min))
    }

    /// Pose la rangée le long du plus petit côté et renvoie l'espace restant.
    private static func place(row: Range<Int>, areas: [Double], sum: Double,
                              in rect: CGRect, into result: inout [CGRect]) -> CGRect {
        if rect.width >= rect.height {
            // Colonne verticale à gauche.
            let width = CGFloat(sum) / rect.height
            var y = rect.minY
            for i in row {
                let height = CGFloat(areas[i]) / width
                result[i] = CGRect(x: rect.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: max(0, rect.width - width), height: rect.height)
        } else {
            // Rangée horizontale en haut.
            let height = CGFloat(sum) / rect.width
            var x = rect.minX
            for i in row {
                let width = CGFloat(areas[i]) / height
                result[i] = CGRect(x: x, y: rect.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(0, rect.height - height))
        }
    }
}
```

- [ ] **Étape 4 : vérifier que les tests passent**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : `✔ Test run with 18 tests passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Sources/StorageCore/Treemap/TreemapLayout.swift Tests/StorageCoreTests/TreemapLayoutTests.swift
git commit -m "feat(core): algorithme squarified du treemap" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 4 : scène du treemap (deux niveaux, petits éléments, « Système et autres »)

**Fichiers :**
- Créer : `Sources/StorageCore/Treemap/TreemapScene.swift`
- Test : `Tests/StorageCoreTests/TreemapSceneTests.swift`

**Interfaces :**
- Utilise : `FileTree` (tâche 2), `TreemapLayout.squarify` (tâche 3).
- Fournit :
  - `public struct TreemapItem: Sendable, Equatable`, avec `content: Content`, `rect: CGRect`, `depth: Int` (0 ou 1), `kind: ContentKind`, `size: UInt64`, `label: String`, et `var node: NodeID?`.
  - `TreemapItem.Content` : `.node(NodeID)`, `.smallItems(count: Int)`, `.systemOther`.
  - `public enum TreemapScene` : `static func build(tree:node:in:systemOtherSize:) -> [TreemapItem]`, qui renvoie d'abord les éléments de niveau 0 puis ceux de niveau 1, et `static func hitTest(_:in:) -> TreemapItem?`, qui renvoie l'élément le plus profond sous le point.
  - Constantes : `minimumItemArea = 36`, `minimumNestingSide = 40`, `headerHeight = 16`, `padding = 2`.

Règles mises en œuvre (spec 5.1) :
- Les enfants dont l'aire estimée est inférieure à 36 pt² sont regroupés en un seul bloc « N petits éléments ».
- Un **dossier** de niveau 0 d'au moins 40 × 40 pt affiche ses enfants à l'intérieur, sous un bandeau de 16 pt. Un **paquet** n'est jamais ouvert.

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/StorageCoreTests/TreemapSceneTests.swift` :

```swift
import CoreGraphics
import Testing
@testable import StorageCore

@Suite struct TreemapSceneTests {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func topLevelItemsMatchChildren() {
        var tree = FileTree(rootPath: "/r")
        let a = tree.append(name: "a.mov", parent: tree.root, type: .file, kind: .video, size: 500, modDate: 0)
        let b = tree.append(name: "b.pdf", parent: tree.root, type: .file, kind: .document, size: 300, modDate: 0)
        let c = tree.append(name: "c.zip", parent: tree.root, type: .file, kind: .archive, size: 200, modDate: 0)
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds)
        #expect(items.map(\.node) == [a, b, c])
        #expect(items.allSatisfy { $0.depth == 0 })
        #expect(items[0].label == "a.mov")
        #expect(items[0].kind == .video)
        #expect(items[0].size == 500)
    }

    @Test func tinyChildrenAreGroupedIntoOneBlock() {
        var tree = FileTree(rootPath: "/r")
        let big = tree.append(name: "big", parent: tree.root, type: .file, kind: .other, size: 1_000_000, modDate: 0)
        for i in 0..<50 {
            tree.append(name: "t\(i)", parent: tree.root, type: .file, kind: .other, size: 1, modDate: 0)
        }
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds)
        #expect(items.count == 2)
        #expect(items[0].node == big)
        #expect(items[1].content == .smallItems(count: 50))
        #expect(items[1].label == "50 petits éléments")
        #expect(items[1].size == 50)
    }

    @Test func largeDirectoriesShowTheirChildrenInside() {
        var tree = FileTree(rootPath: "/r")
        let dir = tree.append(name: "dir", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 0)
        let x = tree.append(name: "x.png", parent: dir, type: .file, kind: .image, size: 600, modDate: 0)
        let y = tree.append(name: "y.png", parent: dir, type: .file, kind: .image, size: 400, modDate: 0)
        let pkg = tree.append(name: "App.app", parent: tree.root, type: .package, kind: .app, size: 1000, modDate: 0)
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds)
        let parentRect = try! #require(items.first { $0.node == dir }).rect
        let nested = items.filter { $0.depth == 1 }
        #expect(nested.map(\.node) == [x, y])
        for item in nested {
            #expect(parentRect.contains(item.rect))
            #expect(item.rect.minY >= parentRect.minY + TreemapScene.headerHeight - 0.01)
        }
        // Un paquet n'est jamais ouvert.
        #expect(!items.contains { $0.depth == 1 && tree.parent(of: $0.node ?? 0) == pkg })
    }

    @Test func systemOtherBlockIsAddedAtTheRoot() {
        var tree = FileTree(rootPath: "/")
        tree.append(name: "Users", parent: tree.root, type: .file, kind: .other, size: 700, modDate: 0)
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds, systemOtherSize: 300)
        let other = try! #require(items.first { $0.content == .systemOther })
        #expect(other.label == "Système et autres")
        #expect(other.kind == .system)
        let ratio = Double(other.rect.width * other.rect.height) / Double(bounds.width * bounds.height)
        #expect(abs(ratio - 0.3) < 0.01)
    }

    @Test func emptyDirectoryGivesNoItems() {
        let tree = FileTree(rootPath: "/vide")
        #expect(TreemapScene.build(tree: tree, node: tree.root, in: bounds).isEmpty)
    }

    @Test func hitTestReturnsTheDeepestItem() {
        var tree = FileTree(rootPath: "/r")
        let dir = tree.append(name: "dir", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 0)
        let only = tree.append(name: "only.bin", parent: dir, type: .file, kind: .other, size: 10, modDate: 0)
        tree.finalize()

        let items = TreemapScene.build(tree: tree, node: tree.root, in: bounds)
        let inside = CGPoint(x: bounds.midX, y: bounds.midY)
        #expect(TreemapScene.hitTest(inside, in: items)?.node == only)
        let header = CGPoint(x: bounds.midX, y: 4)
        #expect(TreemapScene.hitTest(header, in: items)?.node == dir)
        #expect(TreemapScene.hitTest(CGPoint(x: -5, y: -5), in: items) == nil)
    }
}
```

- [ ] **Étape 2 : vérifier que le test échoue**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test --filter TreemapSceneTests`
Résultat attendu : la compilation ÉCHOUE avec `cannot find 'TreemapScene' in scope`.

- [ ] **Étape 3 : écrire l'implémentation**

`Sources/StorageCore/Treemap/TreemapScene.swift` :

```swift
import CoreGraphics

/// Un rectangle à dessiner dans le treemap.
public struct TreemapItem: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case node(NodeID)
        /// Regroupement des éléments trop petits pour être dessinés.
        case smallItems(count: Int)
        /// Espace utilisé non couvert par le scan (affiché seulement à la racine).
        case systemOther
    }

    public var content: Content
    public var rect: CGRect
    /// 0 = enfant direct du dossier affiché, 1 = petit-enfant.
    public var depth: Int
    public var kind: ContentKind
    public var size: UInt64
    public var label: String

    public var node: NodeID? {
        if case let .node(id) = content { return id }
        return nil
    }
}

/// Construit la liste des rectangles à dessiner pour un dossier, sur deux niveaux.
public enum TreemapScene {
    /// Aire estimée (en points²) sous laquelle un élément rejoint le bloc « petits éléments ».
    public static let minimumItemArea: CGFloat = 36
    /// Côté minimal d'un dossier pour afficher son contenu (2e niveau).
    public static let minimumNestingSide: CGFloat = 40
    /// Bandeau réservé au nom du dossier au-dessus de son contenu.
    public static let headerHeight: CGFloat = 16
    public static let padding: CGFloat = 2

    public static func build(tree: FileTree, node: NodeID, in rect: CGRect,
                             systemOtherSize: UInt64 = 0) -> [TreemapItem] {
        let top = layoutLevel(tree: tree, children: tree.children(of: node),
                              systemOtherSize: systemOtherSize, depth: 0, in: rect)
        var items = top
        for item in top {
            guard let id = item.node, tree.nodeType(of: id) == .directory,
                  item.rect.width >= minimumNestingSide, item.rect.height >= minimumNestingSide else { continue }
            let inner = CGRect(x: item.rect.minX + padding,
                               y: item.rect.minY + headerHeight,
                               width: item.rect.width - 2 * padding,
                               height: item.rect.height - headerHeight - padding)
            guard inner.width > 0, inner.height > 0 else { continue }
            items += layoutLevel(tree: tree, children: tree.children(of: id),
                                 systemOtherSize: 0, depth: 1, in: inner)
        }
        return items
    }

    /// L'élément le plus profond sous le point, s'il y en a un.
    public static func hitTest(_ point: CGPoint, in items: [TreemapItem]) -> TreemapItem? {
        items.last { $0.rect.contains(point) }
    }

    private struct Entry {
        var content: TreemapItem.Content
        var size: UInt64
        var kind: ContentKind
        var label: String
    }

    private static func layoutLevel(tree: FileTree, children: [NodeID], systemOtherSize: UInt64,
                                    depth: Int, in rect: CGRect) -> [TreemapItem] {
        let childTotal = children.reduce(UInt64(0)) { $0 + tree.size(of: $1) }
        let total = Double(childTotal + systemOtherSize)
        guard total > 0, rect.width > 0, rect.height > 0 else { return [] }
        let areaPerByte = Double(rect.width * rect.height) / total

        var entries: [Entry] = []
        var smallCount = 0
        var smallSize: UInt64 = 0
        for child in children { // déjà triés par taille décroissante
            let size = tree.size(of: child)
            guard size > 0 else { continue }
            if smallCount > 0 || Double(size) * areaPerByte < Double(minimumItemArea) {
                smallCount += 1
                smallSize += size
            } else {
                entries.append(Entry(content: .node(child), size: size,
                                     kind: tree.kind(of: child), label: tree.name(of: child)))
            }
        }
        if systemOtherSize > 0 {
            entries.append(Entry(content: .systemOther, size: systemOtherSize, kind: .system, label: "Système et autres"))
        }
        if smallCount > 0 {
            let label = smallCount == 1 ? "1 petit élément" : "\(smallCount) petits éléments"
            entries.append(Entry(content: .smallItems(count: smallCount), size: smallSize, kind: .other, label: label))
        }
        entries.sort { $0.size > $1.size }

        let rects = TreemapLayout.squarify(sizes: entries.map { Double($0.size) }, in: rect)
        return zip(entries, rects).map { entry, r in
            TreemapItem(content: entry.content, rect: r, depth: depth,
                        kind: entry.kind, size: entry.size, label: entry.label)
        }
    }
}
```

- [ ] **Étape 4 : vérifier que les tests passent**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : `✔ Test run with 24 tests passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Sources/StorageCore/Treemap/TreemapScene.swift Tests/StorageCoreTests/TreemapSceneTests.swift
git commit -m "feat(core): scène du treemap sur deux niveaux" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 5 : lecture rapide d'un dossier (`getattrlistbulk`)

**Fichiers :**
- Créer : `Sources/StorageCore/Scan/DirectoryReader.swift`
- Créer : `Tests/StorageCoreTests/TestSupport.swift`
- Test : `Tests/StorageCoreTests/DirectoryReaderTests.swift`

**Interfaces :**
- Utilise : rien (Darwin).
- Fournit (interne au module) :
  - `struct RawEntry: Sendable, Equatable`, avec `name`, `kind: Kind` (`.file`, `.directory`, `.symlink`, `.other`), `allocatedSize: UInt64` (0 pour un dossier), `modificationTime: Int64`, `linkCount: UInt32`, `fileID: UInt64`.
  - `struct DirectoryListing: Sendable`, avec `device: Int32` et `entries: [RawEntry]`.
  - `enum DirectoryReadError: Error, Equatable { case posix(Int32) }`.
  - `enum DirectoryReader`, avec `static func read(path: String) throws -> DirectoryListing`.
- Utilitaires de test : `final class TempDir` (avec `path`, `file(_:bytes:)`, `dir(_:)`), `allocatedSize(_:) -> UInt64`, `deviceID(_:) -> Int32`, `final class LockedBox<Value>: @unchecked Sendable`.

Points délicats, déjà validés sur ce Mac :
- **Décodage selon le masque.** Chaque champ n'est lu que si son bit figure dans `ATTR_CMN_RETURNED_ATTRS` (voir les notes d'exécution). On ne demande **pas** `ATTR_CMN_ERROR` et on passe `0` en options.
- **Ouverture du dossier** avec `O_NOFOLLOW`. Le chemin racine doit donc être canonique : les tests résolvent `/var` vers `/private/var`.
- **Garde-fou sur les noms.** Un nom vide, `.`, `..`, ou contenant `/` ou un octet nul est ignoré. Sans ce garde-fou, un nom mal décodé ferait relire le dossier parent à l'infini : c'est ce qui bloquait le premier prototype.

- [ ] **Étape 1 : écrire les utilitaires de test**

`Tests/StorageCoreTests/TestSupport.swift` :

```swift
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
```

- [ ] **Étape 2 : écrire le test qui échoue**

`Tests/StorageCoreTests/DirectoryReaderTests.swift` :

```swift
import Foundation
import Testing
@testable import StorageCore

@Suite struct DirectoryReaderTests {
    @Test func readsNamesKindsAndAllocatedSizes() throws {
        let tmp = try TempDir()
        let file = try tmp.file("doc.txt", bytes: 10_000)
        try tmp.dir("sub")
        try FileManager.default.createSymbolicLink(atPath: tmp.path + "/lien", withDestinationPath: file)

        let listing = try DirectoryReader.read(path: tmp.path)
        let byName = Dictionary(uniqueKeysWithValues: listing.entries.map { ($0.name, $0) })

        #expect(byName.count == 3)
        #expect(byName["doc.txt"]?.kind == .file)
        #expect(byName["doc.txt"]?.allocatedSize == allocatedSize(file))
        #expect(byName["doc.txt"]?.linkCount == 1)
        #expect(byName["sub"]?.kind == .directory)
        #expect(byName["sub"]?.allocatedSize == 0)
        #expect(byName["lien"]?.kind == .symlink)

        let attrs = try FileManager.default.attributesOfItem(atPath: file)
        let mod = try #require(attrs[.modificationDate] as? Date)
        #expect(byName["doc.txt"]?.modificationTime == Int64(mod.timeIntervalSince1970))
        #expect(listing.device == deviceID(tmp.path))
    }

    @Test func readsNonAsciiNames() throws {
        let tmp = try TempDir()
        try tmp.file("café été 🎉.txt", bytes: 1)
        let listing = try DirectoryReader.read(path: tmp.path)
        #expect(listing.entries.map(\.name) == ["café été 🎉.txt"])
    }

    @Test func readsDirectoriesLargerThanOneBuffer() throws {
        let tmp = try TempDir()
        let longName = String(repeating: "n", count: 120)
        for i in 0..<3000 { try tmp.file("\(longName)-\(i)", bytes: 0) }
        let listing = try DirectoryReader.read(path: tmp.path)
        #expect(listing.entries.count == 3000)
        #expect(Set(listing.entries.map(\.name)).count == 3000)
    }

    @Test func reportsPosixErrors() throws {
        let tmp = try TempDir()
        let file = try tmp.file("f", bytes: 1)
        #expect(throws: DirectoryReadError.posix(ENOENT)) { try DirectoryReader.read(path: tmp.path + "/absent") }
        #expect(throws: DirectoryReadError.posix(ENOTDIR)) { try DirectoryReader.read(path: file) }
    }
}
```

- [ ] **Étape 3 : vérifier que le test échoue**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test --filter DirectoryReaderTests`
Résultat attendu : la compilation ÉCHOUE avec `cannot find 'DirectoryReader' in scope`.

- [ ] **Étape 4 : écrire l'implémentation**

`Sources/StorageCore/Scan/DirectoryReader.swift` :

```swift
import Darwin

/// Une entrée brute lue dans un dossier.
struct RawEntry: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case file, directory, symlink, other }

    var name: String
    var kind: Kind
    /// Taille réellement allouée sur le disque (0 pour les dossiers).
    var allocatedSize: UInt64
    /// Date de modification, en secondes depuis 1970.
    var modificationTime: Int64
    var linkCount: UInt32
    var fileID: UInt64
}

struct DirectoryListing: Sendable {
    /// Identifiant du volume qui contient le dossier.
    var device: Int32
    var entries: [RawEntry]
}

enum DirectoryReadError: Error, Equatable {
    case posix(Int32)
}

/// Lecture rapide d'un dossier par lots via `getattrlistbulk(2)`.
enum DirectoryReader {
    private static let bufferSize = 256 * 1024

    static func read(path: String) throws -> DirectoryListing {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DirectoryReadError.posix(errno) }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0 else { throw DirectoryReadError.posix(errno) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FILEID)
        request.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var entries: [RawEntry] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count < 0 {
                if errno == EINTR { continue }
                throw DirectoryReadError.posix(errno)
            }
            if count == 0 { break }

            var entryStart = buffer
            for _ in 0..<count {
                let length = entryStart.loadUnaligned(as: UInt32.self)
                defer { entryStart += Int(length) }
                if let entry = parseEntry(at: entryStart + MemoryLayout<UInt32>.size) {
                    entries.append(entry)
                }
            }
        }
        return DirectoryListing(device: info.st_dev, entries: entries)
    }

    /// Décode une entrée. Seuls les attributs signalés dans `ATTR_CMN_RETURNED_ATTRS` sont présents
    /// (un dossier n'a pas d'attributs de fichier), dans l'ordre de leurs bits.
    private static func parseEntry(at start: UnsafeMutableRawPointer) -> RawEntry? {
        var field = start
        let returned = field.loadUnaligned(as: attribute_set_t.self)
        field += MemoryLayout<attribute_set_t>.size

        guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { return nil }
        let nameRef = field.loadUnaligned(as: attrreference_t.self)
        let nameStart = field + Int(nameRef.attr_dataoffset)
        let nameLength = max(0, Int(nameRef.attr_length) - 1) // sans le NUL final
        let name = String(decoding: UnsafeRawBufferPointer(start: nameStart, count: nameLength), as: UTF8.self)
        field += MemoryLayout<attrreference_t>.size
        // Garde-fou : un nom invalide ferait relire le dossier parent à l'infini.
        guard !name.isEmpty, name != ".", name != "..", !name.utf8.contains(0), !name.utf8.contains(0x2F) else {
            return nil
        }

        var objType: fsobj_type_t = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            objType = field.loadUnaligned(as: fsobj_type_t.self)
            field += MemoryLayout<fsobj_type_t>.size
        }
        var modTime = timespec()
        if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
            modTime = field.loadUnaligned(as: timespec.self)
            field += MemoryLayout<timespec>.size
        }
        var fileID: UInt64 = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
            fileID = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }
        var linkCount: UInt32 = 1
        if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
            linkCount = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }
        var allocSize: off_t = 0
        if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
            allocSize = field.loadUnaligned(as: off_t.self)
            field += MemoryLayout<off_t>.size
        }

        let kind: RawEntry.Kind
        switch objType {
        case fsobj_type_t(VREG.rawValue): kind = .file
        case fsobj_type_t(VDIR.rawValue): kind = .directory
        case fsobj_type_t(VLNK.rawValue): kind = .symlink
        default: kind = .other
        }

        return RawEntry(
            name: name,
            kind: kind,
            allocatedSize: kind == .file ? UInt64(max(0, allocSize)) : 0,
            modificationTime: Int64(modTime.tv_sec),
            linkCount: linkCount,
            fileID: fileID
        )
    }
}
```

- [ ] **Étape 5 : vérifier que les tests passent**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : `✔ Test run with 28 tests passed`. Le test `readsDirectoriesLargerThanOneBuffer` crée 3 000 fichiers et prend environ 0,5 s.

- [ ] **Étape 6 : commiter**

```bash
git add Sources/StorageCore/Scan/DirectoryReader.swift Tests/StorageCoreTests/TestSupport.swift Tests/StorageCoreTests/DirectoryReaderTests.swift
git commit -m "feat(core): lecture de dossiers par lots via getattrlistbulk" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 6 : DiskScanner, le parcours parallèle

**Fichiers :**
- Créer : `Sources/StorageCore/Scan/DiskScanner.swift`
- Test : `Tests/StorageCoreTests/DiskScannerTests.swift`

**Interfaces :**
- Utilise : `DirectoryReader` (tâche 5), `PackageDetector` et `ContentKind.classify` (tâche 1), `FileTree` (tâche 2).
- Fournit :
  - `public struct ScanProgress: Sendable, Equatable`, avec `entryCount: Int`, `byteCount: UInt64`, `currentPath: String`, et `init(entryCount:byteCount:currentPath:)` dont tous les paramètres ont une valeur par défaut.
  - `public enum ScanError: Error, Equatable { case rootUnreadable(path: String, errno: Int32) }`.
  - `public struct DiskScanner: Sendable`, avec `static let defaultExcludedPaths: Set<String>`, `var excludedPaths`, `var maxConcurrency`, `init(excludedPaths:maxConcurrency:)` (valeurs par défaut : les exclusions de la spec, et `min(8, max(2, cœurs − 1))`), et `func scan(root: String, progress: @Sendable (ScanProgress) -> Void = { _ in }) async throws -> FileTree`.
  - Interne : `static func packageSize(at:) -> UInt64` et `static func deviceID(of:) -> Int32?`.

Conception :
- **Une boucle coordinatrice**, et elle seule, modifie le `FileTree`. Elle garde au plus `maxConcurrency` tâches enfants actives dans un `withThrowingTaskGroup`. Chaque tâche enfant lit **un** dossier, ou calcule la taille d'**un** paquet, et renvoie un résultat `Sendable`.
- **Filtrage par volume.** Une liste est ignorée si son volume n'est ni celui de la racine, ni celui de `/`, ni celui de `/System/Volumes/Data`. Cela écarte par exemple les montages `nullfs` d'*AppTranslocation*, constatés sous `/private/var/folders`.
- **Liens physiques** : la clé (volume, inode) n'est comptée qu'une fois.
- **Liens symboliques** et autres types : ils sont ignorés et ne créent aucun nœud.
- **Annulation** : `Task.checkCancellation()` est appelé au démarrage et après chaque résultat.
- **Progression** : elle est publiée au plus toutes les 100 ms, puis une dernière fois à la fin.

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/StorageCoreTests/DiskScannerTests.swift` :

```swift
import Foundation
import Testing
@testable import StorageCore

@Suite struct DiskScannerTests {
    @Test func buildsTheTreeWithAllocatedSizes() async throws {
        let tmp = try TempDir()
        let f1 = try tmp.file("a/one.bin", bytes: 10_000)
        let f2 = try tmp.file("a/b/two.bin", bytes: 5_000)
        let f3 = try tmp.file("three.txt", bytes: 1)

        let tree = try await DiskScanner().scan(root: tmp.path)

        #expect(tree.rootPath == tmp.path)
        #expect(tree.totalSize == allocatedSize(f1) + allocatedSize(f2) + allocatedSize(f3))
        let a = try #require(tree.node(atPath: tmp.path + "/a"))
        #expect(tree.nodeType(of: a) == .directory)
        #expect(tree.size(of: a) == allocatedSize(f1) + allocatedSize(f2))
        let two = try #require(tree.node(atPath: f2))
        #expect(tree.nodeType(of: two) == .file)
        #expect(tree.size(of: two) == allocatedSize(f2))
        #expect(tree.children(of: tree.root).first == a)
        #expect(tree.unreadablePaths.isEmpty)
    }

    @Test func countsHardLinksOnce() async throws {
        let tmp = try TempDir()
        let original = try tmp.file("x.bin", bytes: 100_000)
        try FileManager.default.linkItem(atPath: original, toPath: tmp.path + "/y.bin")

        let tree = try await DiskScanner().scan(root: tmp.path)

        #expect(tree.node(atPath: original) != nil)
        #expect(tree.node(atPath: tmp.path + "/y.bin") != nil)
        #expect(tree.totalSize == allocatedSize(original))
    }

    @Test func ignoresSymlinks() async throws {
        let tmp = try TempDir()
        let target = try tmp.file("cible.bin", bytes: 50_000)
        try FileManager.default.createSymbolicLink(atPath: tmp.path + "/lien", withDestinationPath: target)

        let tree = try await DiskScanner().scan(root: tmp.path)

        #expect(tree.node(atPath: tmp.path + "/lien") == nil)
        #expect(tree.totalSize == allocatedSize(target))
    }

    @Test func measuresSparseFilesByAllocatedSize() async throws {
        let tmp = try TempDir()
        let path = tmp.path + "/creux.raw"
        FileManager.default.createFile(atPath: path, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.seek(toOffset: 50_000_000)
        try handle.write(contentsOf: Data([1]))
        try handle.close()

        let tree = try await DiskScanner().scan(root: tmp.path)

        let node = try #require(tree.node(atPath: path))
        #expect(tree.size(of: node) == allocatedSize(path))
        #expect(tree.size(of: node) < 1_000_000)
    }

    @Test func treatsPackagesAsLeaves() async throws {
        let tmp = try TempDir()
        let binary = try tmp.file("Outil.app/Contents/MacOS/outil", bytes: 20_000)
        let plist = try tmp.file("Outil.app/Contents/Info.plist", bytes: 300)

        let tree = try await DiskScanner().scan(root: tmp.path)

        let app = try #require(tree.node(atPath: tmp.path + "/Outil.app"))
        #expect(tree.nodeType(of: app) == .package)
        #expect(tree.kind(of: app) == .app)
        #expect(tree.children(of: app).isEmpty)
        #expect(tree.size(of: app) == allocatedSize(binary) + allocatedSize(plist))
    }

    @Test func recordsUnreadableDirectories() async throws {
        let tmp = try TempDir()
        let locked = try tmp.dir("verrou")
        try tmp.file("verrou/cache.bin", bytes: 1_000)
        chmod(locked, 0o000)
        defer { chmod(locked, 0o755) }

        let tree = try await DiskScanner().scan(root: tmp.path)

        #expect(tree.unreadablePaths == [locked])
        #expect(tree.node(atPath: locked) != nil)
    }

    @Test func skipsExcludedPaths() async throws {
        let tmp = try TempDir()
        try tmp.file("garde/f.bin", bytes: 1_000)
        try tmp.file("ignore/f.bin", bytes: 1_000)

        let tree = try await DiskScanner(excludedPaths: [tmp.path + "/ignore"]).scan(root: tmp.path)

        #expect(tree.node(atPath: tmp.path + "/garde") != nil)
        #expect(tree.node(atPath: tmp.path + "/ignore") == nil)
    }

    @Test func throwsWhenTheRootIsUnreadable() async throws {
        let tmp = try TempDir()
        let missing = tmp.path + "/absent"
        await #expect(throws: ScanError.rootUnreadable(path: missing, errno: ENOENT)) {
            try await DiskScanner().scan(root: missing)
        }
    }

    @Test func stopsWhenCancelled() async throws {
        let tmp = try TempDir()
        for i in 0..<200 { try tmp.file("d\(i)/f.bin", bytes: 10) }
        let root = tmp.path

        let task = Task { try await DiskScanner().scan(root: root) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func reportsProgress() async throws {
        let tmp = try TempDir()
        try tmp.file("a/f.bin", bytes: 4_096)
        let last = LockedBox<ScanProgress?>(nil)

        let tree = try await DiskScanner().scan(root: tmp.path) { last.value = $0 }

        let progress = try #require(last.value)
        #expect(progress.entryCount == 2)
        #expect(progress.byteCount == tree.totalSize)
    }
}
```

- [ ] **Étape 2 : vérifier que le test échoue**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test --filter DiskScannerTests`
Résultat attendu : la compilation ÉCHOUE avec `cannot find 'DiskScanner' in scope`.

- [ ] **Étape 3 : écrire l'implémentation**

`Sources/StorageCore/Scan/DiskScanner.swift` :

```swift
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
```

- [ ] **Étape 4 : vérifier que les tests passent**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : `✔ Test run with 38 tests passed`. Si la limite de 300 s est atteinte (exit 142), un test boucle : relance avec `rtk proxy` pour voir lequel ne termine pas.

- [ ] **Étape 5 : commiter**

```bash
git add Sources/StorageCore/Scan/DiskScanner.swift Tests/StorageCoreTests/DiskScannerTests.swift
git commit -m "feat(core): DiskScanner, parcours parallèle du disque" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 7 : ScanStore, la persistance du dernier scan

**Fichiers :**
- Créer : `Sources/StorageCore/Persistence/ScanStore.swift`
- Test : `Tests/StorageCoreTests/ScanStoreTests.swift`

**Interfaces :**
- Utilise : `FileTree`, y compris ses tableaux internes et son `init` en pré-ordre (tâche 2), et `TempDir` (tâche 5).
- Fournit :
  - `public enum ScanStoreError: Error, Equatable { case corrupted, unsupportedVersion(UInt32) }`.
  - `public struct ScanStore: Sendable`, avec `static let formatVersion: UInt32 = 1`, `let fileURL: URL`, `init(directory: URL = ScanStore.defaultDirectory)`, `static var defaultDirectory: URL` (`~/Library/Application Support/StorageMonitor/`), `func save(_:) throws` et `func load() throws -> FileTree?`. `load()` renvoie `nil` s'il n'y a pas encore de fichier.
  - Interne : `static func encode(_:) -> Data`, `static func decode(_:) throws -> FileTree`, `BinaryWriter` et `BinaryReader`.

Format : `"SMSC"`, `UInt32` version, chemin racine, date du scan (bits d'un `Double`), chemins inaccessibles, puis les nœuds vivants en **pré-ordre** : parent (`Int32`), type, kind, taille, date, nom. L'ensemble est en petit-boutiste, compressé en LZFSE et écrit de façon atomique.

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/StorageCoreTests/ScanStoreTests.swift` :

```swift
import Foundation
import Testing
@testable import StorageCore

private func sampleTree() -> FileTree {
    var tree = FileTree(rootPath: "/data", scanDate: Date(timeIntervalSince1970: 1_790_000_000.25))
    let dir = tree.append(name: "Vidéos", parent: tree.root, type: .directory, kind: .other, size: 0, modDate: 100)
    tree.append(name: "film.mov", parent: dir, type: .file, kind: .video, size: 7_000, modDate: 101)
    let gone = tree.append(name: "supprimé.bin", parent: dir, type: .file, kind: .other, size: 500, modDate: 102)
    tree.append(name: "Outil.app", parent: tree.root, type: .package, kind: .app, size: 3_000, modDate: 103)
    tree.unreadablePaths = ["/data/verrou"]
    tree.finalize()
    tree.remove([gone])
    return tree
}

@Suite struct ScanStoreTests {
    @Test func savesAndLoadsAnIdenticalTree() throws {
        let tmp = try TempDir()
        let store = ScanStore(directory: URL(fileURLWithPath: tmp.path + "/support"))
        let original = sampleTree()

        try store.save(original)
        let loaded = try #require(try store.load())

        #expect(loaded.rootPath == "/data")
        #expect(loaded.scanDate == original.scanDate)
        #expect(loaded.unreadablePaths == ["/data/verrou"])
        #expect(loaded.liveNodeCount == original.liveNodeCount)
        #expect(loaded.totalSize == original.totalSize)
        for path in ["/data/Vidéos", "/data/Vidéos/film.mov", "/data/Outil.app"] {
            let a = try #require(original.node(atPath: path))
            let b = try #require(loaded.node(atPath: path))
            #expect(loaded.size(of: b) == original.size(of: a))
            #expect(loaded.nodeType(of: b) == original.nodeType(of: a))
            #expect(loaded.kind(of: b) == original.kind(of: a))
            #expect(loaded.modificationDate(of: b) == original.modificationDate(of: a))
        }
        #expect(loaded.node(atPath: "/data/Vidéos/supprimé.bin") == nil)
        let rootChildren = loaded.children(of: loaded.root).map { loaded.name(of: $0) }
        #expect(rootChildren == ["Vidéos", "Outil.app"])
    }

    @Test func loadReturnsNilWithoutASavedScan() throws {
        let tmp = try TempDir()
        let store = ScanStore(directory: URL(fileURLWithPath: tmp.path))
        #expect(try store.load() == nil)
    }

    @Test func rejectsCorruptedFiles() throws {
        let tmp = try TempDir()
        let store = ScanStore(directory: URL(fileURLWithPath: tmp.path))
        try Data([1, 2, 3, 4, 5]).write(to: store.fileURL)
        #expect(throws: ScanStoreError.corrupted) { try store.load() }
    }

    @Test func rejectsTruncatedData() throws {
        let raw = ScanStore.encode(sampleTree())
        #expect(throws: ScanStoreError.corrupted) { try ScanStore.decode(raw.prefix(raw.count - 3)) }
    }

    @Test func rejectsOtherFormatVersions() throws {
        var raw = ScanStore.encode(sampleTree())
        raw[4] = 99
        #expect(throws: ScanStoreError.unsupportedVersion(99)) { try ScanStore.decode(raw) }
    }
}
```

- [ ] **Étape 2 : vérifier que le test échoue**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test --filter ScanStoreTests`
Résultat attendu : la compilation ÉCHOUE avec `cannot find 'ScanStore' in scope`.

- [ ] **Étape 3 : écrire l'implémentation**

`Sources/StorageCore/Persistence/ScanStore.swift` :

```swift
import Foundation

public enum ScanStoreError: Error, Equatable {
    case corrupted
    case unsupportedVersion(UInt32)
}

/// Sauvegarde et rechargement du dernier scan (format binaire versionné, compressé en LZFSE).
public struct ScanStore: Sendable {
    public static let formatVersion: UInt32 = 1
    static let magic: [UInt8] = Array("SMSC".utf8)

    public let fileURL: URL

    public init(directory: URL = ScanStore.defaultDirectory) {
        fileURL = directory.appendingPathComponent("last-scan.bin")
    }

    /// `~/Library/Application Support/StorageMonitor/`
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StorageMonitor", isDirectory: true)
    }

    public func save(_ tree: FileTree) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let raw = Self.encode(tree)
        let compressed = try (raw as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: fileURL, options: .atomic)
    }

    /// `nil` s'il n'y a pas encore de scan enregistré.
    public func load() throws -> FileTree? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let compressed = try Data(contentsOf: fileURL)
        guard let raw = try? (compressed as NSData).decompressed(using: .lzfse) as Data else {
            throw ScanStoreError.corrupted
        }
        return try Self.decode(raw)
    }

    // MARK: - Format

    /// Nœuds vivants en pré-ordre : un parent précède toujours ses enfants.
    static func encode(_ tree: FileTree) -> Data {
        var writer = BinaryWriter()
        writer.bytes(magic)
        writer.integer(formatVersion)
        writer.string(tree.rootPath)
        writer.integer(tree.scanDate.timeIntervalSince1970.bitPattern)
        writer.integer(UInt32(tree.unreadablePaths.count))
        for path in tree.unreadablePaths { writer.string(path) }

        var order: [NodeID] = []
        order.reserveCapacity(tree.storageCount)
        var newIndex = [Int32](repeating: -1, count: tree.storageCount)
        var stack: [NodeID] = [tree.root]
        while let node = stack.popLast() {
            newIndex[Int(node)] = Int32(order.count)
            order.append(node)
            stack.append(contentsOf: tree.children(of: node).reversed())
        }

        writer.integer(UInt32(order.count))
        for node in order {
            let parent = tree.parent(of: node).map { newIndex[Int($0)] } ?? -1
            writer.integer(parent)
            writer.integer(tree.nodeType(of: node).rawValue)
            writer.integer(tree.kind(of: node).rawValue)
            writer.integer(tree.size(of: node))
            writer.integer(tree.modDates[Int(node)])
            writer.string(tree.name(of: node))
        }
        return Data(writer.buffer)
    }

    static func decode(_ data: Data) throws -> FileTree {
        var reader = BinaryReader(bytes: [UInt8](data))
        guard try reader.bytes(count: magic.count) == magic else { throw ScanStoreError.corrupted }
        let version = try reader.integer(UInt32.self)
        guard version == formatVersion else { throw ScanStoreError.unsupportedVersion(version) }
        let rootPath = try reader.string()
        let scanDate = Date(timeIntervalSince1970: Double(bitPattern: try reader.integer(UInt64.self)))
        let unreadableCount = Int(try reader.integer(UInt32.self))
        var unreadable: [String] = []
        for _ in 0..<unreadableCount { unreadable.append(try reader.string()) }

        let count = Int(try reader.integer(UInt32.self))
        guard count >= 1 else { throw ScanStoreError.corrupted }
        var names: [String] = [], parents: [NodeID] = [], types: [NodeType] = []
        var kinds: [ContentKind] = [], sizes: [UInt64] = [], modDates: [Int64] = []
        names.reserveCapacity(count); parents.reserveCapacity(count); types.reserveCapacity(count)
        kinds.reserveCapacity(count); sizes.reserveCapacity(count); modDates.reserveCapacity(count)

        for i in 0..<count {
            let parent = try reader.integer(Int32.self)
            guard (i == 0 && parent == -1) || (i > 0 && parent >= 0 && Int(parent) < i) else {
                throw ScanStoreError.corrupted
            }
            guard let type = NodeType(rawValue: try reader.integer(UInt8.self)),
                  let kind = ContentKind(rawValue: try reader.integer(UInt8.self)) else {
                throw ScanStoreError.corrupted
            }
            parents.append(parent)
            types.append(type)
            kinds.append(kind)
            sizes.append(try reader.integer(UInt64.self))
            modDates.append(try reader.integer(Int64.self))
            names.append(try reader.string())
        }
        guard reader.isAtEnd else { throw ScanStoreError.corrupted }
        return FileTree(rootPath: rootPath, scanDate: scanDate, unreadablePaths: unreadable,
                        names: names, parents: parents, types: types, kinds: kinds,
                        sizes: sizes, modDates: modDates)
    }
}

struct BinaryWriter {
    private(set) var buffer: [UInt8] = []

    mutating func bytes(_ bytes: [UInt8]) { buffer.append(contentsOf: bytes) }

    mutating func integer<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { buffer.append(contentsOf: $0) }
    }

    mutating func string(_ value: String) {
        let utf8 = Array(value.utf8)
        integer(UInt32(utf8.count))
        buffer.append(contentsOf: utf8)
    }
}

struct BinaryReader {
    let bytes: [UInt8]
    private var offset = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func bytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw ScanStoreError.corrupted }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func integer<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= bytes.count else { throw ScanStoreError.corrupted }
        let value = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        offset += size
        return T(littleEndian: value)
    }

    mutating func string() throws -> String {
        let length = Int(try integer(UInt32.self))
        guard offset + length <= bytes.count else { throw ScanStoreError.corrupted }
        defer { offset += length }
        return String(decoding: bytes[offset..<offset + length], as: UTF8.self)
    }
}
```

- [ ] **Étape 4 : vérifier que les tests passent**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : `✔ Test run with 43 tests passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Sources/StorageCore/Persistence/ScanStore.swift Tests/StorageCoreTests/ScanStoreTests.swift
git commit -m "feat(core): persistance binaire versionnée du dernier scan" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 8 : infos du volume et détection de l'Accès complet au disque

**Fichiers :**
- Créer : `Sources/StorageCore/System/VolumeInfo.swift`
- Créer : `Sources/StorageCore/System/FullDiskAccess.swift`
- Test : `Tests/StorageCoreTests/SystemTests.swift`

**Interfaces :**
- Utilise : `DirectoryReader` (tâche 5), `TempDir` (tâche 5).
- Fournit :
  - `public struct VolumeInfo: Sendable, Equatable`, avec `name`, `totalCapacity`, `availableCapacity` (espace réellement libre), `availableForImportantUsage` (ce qu'affiche le Finder), `usedCapacity`, `static func current(for path: String = "/") throws -> VolumeInfo` et `static func systemOtherSize(used:scanned:) -> UInt64`.
  - `public enum FullDiskAccess`, avec `static var defaultProbePaths: [String]`, `static func isGranted(probePaths:) -> Bool` et `static let settingsURL: URL`.

Règles :
- **« Système et autres »** = utilisé − scanné, ramené à 0 si le résultat est négatif.
- **Accès accordé** si un dossier sonde protégé par TCC est lisible. **Refusé** si une sonde existante renvoie `EPERM` ou `EACCES`. **Considéré comme accordé** si aucune sonde n'existe, car rien ne permet de conclure.

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/StorageCoreTests/SystemTests.swift` :

```swift
import Foundation
import Testing
@testable import StorageCore

@Suite struct VolumeInfoTests {
    @Test func readsTheBootVolume() throws {
        let info = try VolumeInfo.current(for: "/")
        #expect(info.totalCapacity > 0)
        #expect(info.availableCapacity <= info.totalCapacity)
        #expect(info.usedCapacity == info.totalCapacity - info.availableCapacity)
        #expect(!info.name.isEmpty)
    }

    @Test func systemOtherSizeNeverGoesNegative() {
        #expect(VolumeInfo.systemOtherSize(used: 100, scanned: 70) == 30)
        #expect(VolumeInfo.systemOtherSize(used: 70, scanned: 100) == 0)
    }
}

@Suite struct FullDiskAccessTests {
    @Test func readableProbeMeansGranted() throws {
        let tmp = try TempDir()
        #expect(FullDiskAccess.isGranted(probePaths: [tmp.path]))
    }

    @Test func deniedProbeMeansNotGranted() throws {
        let tmp = try TempDir()
        let locked = try tmp.dir("protégé")
        chmod(locked, 0o000)
        defer { chmod(locked, 0o755) }
        #expect(!FullDiskAccess.isGranted(probePaths: [locked]))
    }

    @Test func missingProbesAreInconclusive() throws {
        let tmp = try TempDir()
        #expect(FullDiskAccess.isGranted(probePaths: [tmp.path + "/absent"]))
    }
}
```

- [ ] **Étape 2 : vérifier que le test échoue**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test --filter VolumeInfoTests`
Résultat attendu : la compilation ÉCHOUE avec `cannot find 'VolumeInfo' in scope`.

- [ ] **Étape 3 : écrire l'implémentation**

`Sources/StorageCore/System/VolumeInfo.swift` :

```swift
import Foundation

/// Capacités du volume qui contient un chemin.
public struct VolumeInfo: Sendable, Equatable {
    public var name: String
    public var totalCapacity: UInt64
    /// Espace réellement libre.
    public var availableCapacity: UInt64
    /// Espace libre tel que l'affiche le Finder (inclut le purgeable).
    public var availableForImportantUsage: UInt64

    public init(name: String, totalCapacity: UInt64, availableCapacity: UInt64, availableForImportantUsage: UInt64) {
        self.name = name
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.availableForImportantUsage = availableForImportantUsage
    }

    public var usedCapacity: UInt64 {
        totalCapacity > availableCapacity ? totalCapacity - availableCapacity : 0
    }

    public static func current(for path: String = "/") throws -> VolumeInfo {
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        let available = UInt64(max(0, values.volumeAvailableCapacity ?? 0))
        return VolumeInfo(
            name: values.volumeLocalizedName ?? "Macintosh HD",
            totalCapacity: UInt64(max(0, values.volumeTotalCapacity ?? 0)),
            availableCapacity: available,
            availableForImportantUsage: UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? Int64(available)))
        )
    }

    /// Espace utilisé non couvert par le scan : snapshots locaux, swap, purgeable…
    public static func systemOtherSize(used: UInt64, scanned: UInt64) -> UInt64 {
        used > scanned ? used - scanned : 0
    }
}
```

`Sources/StorageCore/System/FullDiskAccess.swift` :

```swift
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
```

- [ ] **Étape 4 : vérifier que les tests passent**

Lance : `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : `✔ Test run with 48 tests passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Sources/StorageCore/System Tests/StorageCoreTests/SystemTests.swift
git commit -m "feat(core): infos du volume et détection de l'Accès complet au disque" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 9 : coque de l'app SwiftUI (modèle, barre latérale, accès au disque, scan)

**Fichiers :**
- Modifier : `Package.swift` (ajout de la cible exécutable)
- Créer : `Sources/StorageMonitor/StorageMonitorApp.swift`
- Créer : `Sources/StorageMonitor/AppModel.swift`
- Créer : `Sources/StorageMonitor/Format.swift`
- Créer : `Sources/StorageMonitor/Views/RootView.swift`
- Créer : `Sources/StorageMonitor/Views/SidebarView.swift`
- Créer : `Sources/StorageMonitor/Views/FullDiskAccessView.swift`
- Créer : `Sources/StorageMonitor/Views/Carte/ScanProgressView.swift`
- Créer : `Sources/StorageMonitor/Views/Carte/CarteView.swift` (version **provisoire**, remplacée à la tâche 11)

**Interfaces :**
- Utilise : toute l'API publique de `StorageCore` (tâches 1 à 8).
- Fournit (utilisé par la tâche 11) :
  - `@MainActor @Observable final class AppModel` :
    - état : `tree: FileTree?`, `treeVersion: Int`, `scanState: ScanState` (`.idle`, `.scanning(ScanProgress)`, `.failed(String)`), `volume: VolumeInfo?`, `hasFullDiskAccess`, `continueWithoutAccess`, `sidebarSelection: SidebarItem?`, `currentNode: NodeID`, `selectedNode: NodeID?` ;
    - propriétés calculées : `needsAccessOnboarding`, `isScanning`, `canGoUp`, `systemOtherSize` ;
    - méthodes : `start() async`, `recheckAccess()`, `refreshVolume()`, `startFullScan()`, `refreshCurrentFolder()`, `cancelScan()`, `dismissError()`, `navigate(to:)`, `goUp()`, `displayName(of:)`, `url(of:) -> URL?`, `revealInFinder(_:)`, `copyPath(_:)`.
  - `enum SidebarItem: Hashable { case carte }`. Le plan 2/2 y ajoutera `suggestions` et `panier`.
  - `enum Format`, avec `bytes(_:)`, `scanDate(_:)` et `percent(_:of:)`, ainsi que `extension ContentKind { var color: Color }`.
  - `struct ScanProgressView(progress:onCancel:)`.

Comportements clés de `AppModel` (spec 3 et 7) :
- **Au lancement** : il relit le dernier scan en arrière-plan (`Task.detached`).
- **Fin de scan** : il remplace l'arbre, ou greffe le sous-arbre pour « Rafraîchir ce dossier » via `tree?.replaceSubtree`. Cette mutation se fait **en place**, sans copier 300 Mo. Il incrémente ensuite `treeVersion`, rafraîchit le volume et sauvegarde en arrière-plan.
- **Annulation ou erreur** : l'arbre précédent est conservé et rien n'est enregistré.
- **Progression** : elle est renvoyée sur le `MainActor` et ignorée si le scan est déjà terminé.

- [ ] **Étape 1 : ajouter la cible exécutable**

`Package.swift`, remplacé intégralement :

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StorageMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StorageCore"),
        .executableTarget(name: "StorageMonitor", dependencies: ["StorageCore"]),
        .testTarget(name: "StorageCoreTests", dependencies: ["StorageCore"]),
    ]
)
```

- [ ] **Étape 2 : écrire le point d'entrée, le modèle et la mise en forme**

`Sources/StorageMonitor/StorageMonitorApp.swift` :

```swift
import AppKit
import SwiftUI

@main
struct StorageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Storage Monitor") {
            RootView(model: model)
        }
        .windowToolbarStyle(.unified)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nécessaire quand l'exécutable est lancé hors d'un bundle .app (swift run).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
```

`Sources/StorageMonitor/AppModel.swift` :

```swift
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
```

`Sources/StorageMonitor/Format.swift` :

```swift
import Foundation
import SwiftUI
import StorageCore

/// Mise en forme des valeurs affichées (suit la langue du système).
enum Format {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    static func scanDate(_ date: Date) -> String {
        "Scan du " + date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    static func percent(_ part: UInt64, of total: UInt64) -> String {
        guard total > 0 else { return "–" }
        return (Double(part) / Double(total)).formatted(.percent.precision(.fractionLength(0...1)))
    }
}

extension ContentKind {
    /// Couleur du treemap et de la légende.
    var color: Color {
        switch self {
        case .video: Color(red: 0.94, green: 0.38, blue: 0.38)
        case .image: Color(red: 0.98, green: 0.62, blue: 0.22)
        case .audio: Color(red: 0.93, green: 0.80, blue: 0.27)
        case .code: Color(red: 0.32, green: 0.78, blue: 0.55)
        case .app: Color(red: 0.38, green: 0.56, blue: 0.98)
        case .archive: Color(red: 0.63, green: 0.47, blue: 0.95)
        case .document: Color(red: 0.27, green: 0.75, blue: 0.85)
        case .system: Color(red: 0.56, green: 0.59, blue: 0.65)
        case .other: Color(red: 0.73, green: 0.75, blue: 0.79)
        }
    }
}
```

- [ ] **Étape 3 : écrire les vues**

`Sources/StorageMonitor/Views/RootView.swift` :

```swift
import AppKit
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.needsAccessOnboarding {
                FullDiskAccessView(model: model)
            } else {
                NavigationSplitView {
                    SidebarView(model: model)
                } detail: {
                    switch model.sidebarSelection ?? .carte {
                    case .carte: CarteView(model: model)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task { await model.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckAccess()
            model.refreshVolume()
        }
    }
}
```

`Sources/StorageMonitor/Views/SidebarView.swift` :

```swift
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
```

`Sources/StorageMonitor/Views/FullDiskAccessView.swift` :

```swift
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
```

`Sources/StorageMonitor/Views/Carte/ScanProgressView.swift` :

```swift
import StorageCore
import SwiftUI

/// Panneau affiché pendant un scan, avec le bouton Annuler.
struct ScanProgressView: View {
    let progress: ScanProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large)
            Text("Analyse du disque…").font(.headline)
            Text("\(progress.entryCount.formatted()) éléments · \(Format.bytes(progress.byteCount))")
                .font(.callout.monospacedDigit())
            Text(progress.currentPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 420)
            Button("Annuler", role: .cancel, action: onCancel)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

`Sources/StorageMonitor/Views/Carte/CarteView.swift` :

```swift
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
```

- [ ] **Étape 4 : compiler**

Lance : `perl -e 'alarm 400; exec @ARGV' swift build --product StorageMonitor`
Résultat attendu : `Build of product 'StorageMonitor' complete!`, sans erreur ni avertissement. Puis lance `perl -e 'alarm 300; exec @ARGV' swift test` : `✔ Test run with 48 tests passed`.

- [ ] **Étape 5 : vérifier à la main**

Lance : `swift run StorageMonitor`. L'app hérite alors des autorisations du terminal.
Vérifie :
1. Une fenêtre « Storage Monitor » s'ouvre avec la barre latérale « Carte » et, en bas, la jauge « Libre : … sur … ».
2. Si l'écran « Accès complet au disque » apparaît, le bouton **Continuer sans** mène à la fenêtre principale.
3. **Scanner le disque** affiche le panneau de progression : compteurs qui avancent, dossier en cours, bouton **Annuler**.
4. **Annuler** pendant le scan ramène à l'état précédent, sans erreur.
5. Un scan complet affiche par exemple « 3 048 505 éléments · 214 Go » et « Scan du … ». Il dure moins de 2 minutes.
6. Quitte (⌘Q) puis relance : le résumé du scan s'affiche immédiatement, sans rescanner.

- [ ] **Étape 6 : commiter**

```bash
git add Package.swift Sources/StorageMonitor
git commit -m "feat(app): coque SwiftUI, accès au disque et scan avec progression" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 10 : bundle .app, signature stable et installation

**Fichiers :**
- Créer : `packaging/Info.plist`
- Créer : `scripts/build-app.sh` (exécutable)
- Créer : `scripts/setup-signing.sh` (exécutable)
- Créer : `README.md`

**Interfaces :**
- Utilise : le produit `StorageMonitor` (tâche 9).
- Fournit :
  - `build/Storage Monitor.app`, signé `Storage Monitor Local` si le certificat existe, sinon en ad hoc avec un avertissement ;
  - `scripts/build-app.sh --install`, qui copie l'app dans `~/Applications`.

Pourquoi un certificat (spec 8) : une signature ad hoc change d'empreinte à chaque build, et macOS oublie alors l'Accès complet au disque. Un certificat stable garde la même *designated requirement*. On utilise `/usr/bin/openssl` (LibreSSL d'Apple) parce que son PKCS#12 est lisible par `security import`, contrairement au format par défaut d'OpenSSL 3. Les deux étapes `openssl` ont été validées sur ce Mac.

- [ ] **Étape 1 : écrire l'Info.plist**

`packaging/Info.plist` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleDisplayName</key>
    <string>Storage Monitor</string>
    <key>CFBundleExecutable</key>
    <string>StorageMonitor</string>
    <key>CFBundleIdentifier</key>
    <string>local.storage-monitor</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Storage Monitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Étape 2 : écrire les scripts**

`scripts/build-app.sh` :

```bash
#!/bin/bash
# Compile Storage Monitor en mode release, assemble le bundle .app et le signe.
# Usage : scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Storage Monitor.app"
IDENTITY="Storage Monitor Local"
BUNDLE_ID="local.storage-monitor"

swift build -c release --product StorageMonitor
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/StorageMonitor" "$APP/Contents/MacOS/StorageMonitor"
cp packaging/Info.plist "$APP/Contents/Info.plist"

if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
    echo "Signé avec « $IDENTITY »."
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    echo "⚠️  Certificat « $IDENTITY » absent : signature ad hoc."
    echo "    L'Accès complet au disque devra être réaccordé après chaque build."
    echo "    Lance scripts/setup-signing.sh une fois pour éviter ça."
fi
codesign --verify --strict "$APP"
echo "App prête : $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Storage Monitor.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installée dans ~/Applications/Storage Monitor.app"
fi
```

`scripts/setup-signing.sh` :

```bash
#!/bin/bash
# Crée (une seule fois) un certificat de signature de code local, « Storage Monitor Local ».
# Une signature stable permet à macOS de conserver l'« Accès complet au disque » d'un build à l'autre.
# macOS demandera ton mot de passe de session pour approuver le certificat.
set -euo pipefail

NAME="Storage Monitor Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl   # LibreSSL d'Apple : son format PKCS#12 est lisible par `security import`

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "Le certificat « $NAME » existe déjà."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/cert.p12" -passout pass:storage-monitor

security import "$WORK/cert.p12" -k "$KEYCHAIN" -P storage-monitor -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

security find-identity -v -p codesigning | grep "\"$NAME\""
echo "Certificat « $NAME » prêt. Relance scripts/build-app.sh."
```

Puis : `chmod +x scripts/build-app.sh scripts/setup-signing.sh`

- [ ] **Étape 3 : écrire le README**

`README.md` :

~~~~markdown
# Storage Monitor

App macOS personnelle : carte de l'espace disque (treemap) et, à terme, suggestions et nettoyage.

## Prérequis

- macOS 14 ou plus récent
- Command Line Tools d'Apple (Swift 6). **Xcode n'est pas nécessaire.**

## Commandes

```bash
swift test                       # tests du moteur (StorageCore)
swift run StorageMonitor         # lancer l'app sans bundle (développement)
scripts/setup-signing.sh         # une seule fois : crée le certificat local « Storage Monitor Local »
scripts/build-app.sh             # compile, assemble et signe build/Storage Monitor.app
scripts/build-app.sh --install   # idem, puis copie dans ~/Applications
```

## Accès complet au disque

Au premier lancement, l'app demande l'« Accès complet au disque » :
Réglages Système › Confidentialité et sécurité › Accès complet au disque › activer « Storage Monitor ».
Grâce au certificat local, l'autorisation survit aux recompilations.

## Données

- Dernier scan : `~/Library/Application Support/StorageMonitor/last-scan.bin`
~~~~

- [ ] **Étape 4 : vérifier le build ad hoc**

Lance : `plutil -lint packaging/Info.plist && scripts/build-app.sh`
Résultat attendu : `packaging/Info.plist: OK`, l'avertissement « Certificat « Storage Monitor Local » absent : signature ad hoc. », puis `App prête : build/Storage Monitor.app`.
Lance : `codesign -dv "build/Storage Monitor.app" 2>&1 | grep -E "Identifier|Signature"`
Résultat attendu : `Identifier=local.storage-monitor` et `Signature=adhoc`.

- [ ] **Étape 5 : créer le certificat (action de l'utilisateur)**

Ce script modifie le trousseau de session et macOS demande le mot de passe : **un agent ne doit pas le lancer lui-même.** Demande à l'utilisateur de taper dans le prompt : `! scripts/setup-signing.sh`. Accepte la fenêtre de confiance du certificat. Lors du premier build, choisis « Toujours autoriser » quand `codesign` demande l'accès à la clé.
Résultat attendu : une ligne `… "Storage Monitor Local"`, puis « Certificat « Storage Monitor Local » prêt. ».

- [ ] **Étape 6 : installer et accorder l'accès (avec l'utilisateur)**

Lance : `scripts/build-app.sh --install`
Résultat attendu : `Signé avec « Storage Monitor Local ».` puis `Installée dans ~/Applications/Storage Monitor.app`.
Demande ensuite à l'utilisateur :
1. d'ouvrir `~/Applications/Storage Monitor.app` : l'écran « Accès complet au disque » s'affiche ;
2. de cliquer **Ouvrir les Réglages**, d'activer « Storage Monitor », puis de revenir (et de relancer l'app si macOS le propose) : la fenêtre principale s'affiche ;
3. de quitter l'app.
Relance alors `scripts/build-app.sh --install`, puis demande à l'utilisateur de rouvrir l'app : **l'écran d'accès ne doit pas réapparaître** (critère de réussite n° 6).

- [ ] **Étape 7 : commiter**

```bash
git add packaging/Info.plist scripts/build-app.sh scripts/setup-signing.sh README.md
git commit -m "build: bundle .app signé avec un certificat local stable" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tâche 11 : écran Carte complet (treemap interactif)

**Fichiers :**
- Créer : `Sources/StorageMonitor/Views/Carte/TreemapView.swift`
- Créer : `Sources/StorageMonitor/Views/Carte/BreadcrumbView.swift`
- Créer : `Sources/StorageMonitor/Views/Carte/LegendView.swift`
- Créer : `Sources/StorageMonitor/Views/Carte/InfoBar.swift`
- Modifier : `Sources/StorageMonitor/Views/Carte/CarteView.swift` (remplacé intégralement)

**Interfaces :**
- Utilise : `AppModel`, `Format`, `ContentKind.color` et `ScanProgressView` (tâche 9), `TreemapScene` et `TreemapItem` (tâche 4).
- Fournit : l'écran Carte final de la spec 5.1. Le plan 2/2 y ajoutera « Ajouter au panier », le ✨ des suggestions et les hachures du panier.

Points de conception :
- **Calcul de la scène.** `TreemapView` ne recalcule la scène que lorsque change la clé `(nœud, treeVersion, taille, systemOther)`, via `.onChange(of:initial:)`. Le survol ne déclenche aucun recalcul.
- **Menu contextuel.** Il agit sur l'élément **survolé**, car `contextMenu` ne fournit pas la position du clic.
- **Raccourcis clavier.** La barre d'espace ouvre Coup d'œil sur la sélection (`onKeyPress`, macOS 14) ; ⌘↑ fait remonter d'un niveau.

- [ ] **Étape 1 : écrire les vues**

`Sources/StorageMonitor/Views/Carte/TreemapView.swift` :

```swift
import StorageCore
import SwiftUI

/// Dessin interactif du treemap du dossier courant.
struct TreemapView: View {
    let model: AppModel
    let tree: FileTree
    @Binding var quickLookURL: URL?

    @State private var items: [TreemapItem] = []
    @State private var hoverPoint: CGPoint?

    private struct SceneKey: Equatable {
        var node: NodeID
        var version: Int
        var size: CGSize
        var systemOther: UInt64
    }

    var body: some View {
        GeometryReader { geo in
            let key = SceneKey(node: model.currentNode, version: model.treeVersion,
                               size: geo.size, systemOther: model.systemOtherSize)
            let hovered = hoverPoint.flatMap { TreemapScene.hitTest($0, in: items) }

            Canvas { context, _ in
                draw(in: context, hovered: hovered)
            }
            .onChange(of: key, initial: true) {
                items = TreemapScene.build(tree: tree, node: key.node,
                                           in: CGRect(origin: .zero, size: key.size),
                                           systemOtherSize: key.systemOther)
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point): hoverPoint = point
                case .ended: hoverPoint = nil
                }
            }
            .onTapGesture(count: 2) { location in
                guard let item = TreemapScene.hitTest(location, in: items) else { return }
                open(item)
            }
            .onTapGesture(count: 1) { location in
                model.selectedNode = TreemapScene.hitTest(location, in: items)?.node
            }
            .contextMenu {
                if let id = hovered?.node {
                    Button("Afficher dans le Finder") { model.revealInFinder(id) }
                    Button("Coup d'œil") { quickLookURL = model.url(of: id) }
                    Button("Copier le chemin") { model.copyPath(id) }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hovered, let point = hoverPoint {
                    tooltip(for: hovered)
                        .offset(x: min(point.x + 14, max(0, geo.size.width - 240)),
                                y: min(point.y + 14, max(0, geo.size.height - 80)))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Double-clic : entrer dans un dossier, sinon Coup d'œil.
    private func open(_ item: TreemapItem) {
        guard let id = item.node else { return }
        if tree.nodeType(of: id) == .directory {
            model.navigate(to: id)
        } else {
            model.selectedNode = id
            quickLookURL = model.url(of: id)
        }
    }

    private func draw(in context: GraphicsContext, hovered: TreemapItem?) {
        for item in items {
            let rect = item.rect.insetBy(dx: 0.5, dy: 0.5)
            guard rect.width >= 1, rect.height >= 1 else { continue }
            let shape = Path(roundedRect: rect, cornerRadius: 2)
            let isContainer = item.depth == 0 && item.node.map { tree.nodeType(of: $0) == .directory } == true
            var color = item.kind.color
            if case .smallItems = item.content { color = color.opacity(0.5) }
            if isContainer { color = color.opacity(0.55) }
            context.fill(shape, with: .color(color))
            context.stroke(shape, with: .color(.black.opacity(0.3)), lineWidth: 0.5)

            if rect.width > 36, rect.height > 14 {
                let text = Text(item.label)
                    .font(.system(size: 10, weight: item.depth == 0 ? .semibold : .regular))
                    .foregroundStyle(.black.opacity(0.8))
                context.draw(text, in: CGRect(x: rect.minX + 4, y: rect.minY + 2,
                                              width: rect.width - 8, height: 13))
            }
        }

        if let hovered {
            context.fill(Path(roundedRect: hovered.rect, cornerRadius: 2), with: .color(.white.opacity(0.18)))
        }
        if let selected = model.selectedNode, let item = items.last(where: { $0.node == selected }) {
            let path = Path(roundedRect: item.rect.insetBy(dx: 1, dy: 1), cornerRadius: 2)
            context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 3)
            context.stroke(path, with: .color(.white), lineWidth: 1.5)
        }
    }

    private func tooltip(for item: TreemapItem) -> some View {
        let parentSize = item.node.flatMap { tree.parent(of: $0) }.map { tree.size(of: $0) }
            ?? tree.size(of: model.currentNode)
        return VStack(alignment: .leading, spacing: 2) {
            Text(item.label).font(.callout.bold()).lineLimit(1)
            Text("\(Format.bytes(item.size)) · \(Format.percent(item.size, of: parentSize)) du dossier")
                .font(.caption)
            if let id = item.node {
                Text("Modifié le \(tree.modificationDate(of: id).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: 230, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
```

`Sources/StorageMonitor/Views/Carte/BreadcrumbView.swift` :

```swift
import StorageCore
import SwiftUI

/// Fil d'Ariane cliquable, de la racine du scan jusqu'au dossier affiché.
struct BreadcrumbView: View {
    let model: AppModel
    let tree: FileTree

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tree.ancestors(of: model.currentNode).enumerated()), id: \.element) { index, id in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                Button(model.displayName(of: id)) { model.navigate(to: id) }
                    .buttonStyle(.plain)
                    .fontWeight(id == model.currentNode ? .semibold : .regular)
                    .lineLimit(1)
            }
        }
    }
}
```

`Sources/StorageMonitor/Views/Carte/LegendView.swift` :

```swift
import StorageCore
import SwiftUI

/// Légende des couleurs du treemap.
struct LegendView: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(ContentKind.allCases, id: \.self) { kind in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(kind.color).frame(width: 10, height: 10)
                    Text(kind.label).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

`Sources/StorageMonitor/Views/Carte/InfoBar.swift` :

```swift
import AppKit
import StorageCore
import SwiftUI

/// Barre du bas : élément sélectionné et actions.
struct InfoBar: View {
    let model: AppModel
    let tree: FileTree
    @Binding var quickLookURL: URL?

    var body: some View {
        HStack(spacing: 10) {
            if let id = model.selectedNode, !tree.isRemoved(id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: tree.path(of: id)))
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tree.name(of: id)).font(.callout.bold()).lineLimit(1)
                    Text(tree.path(of: id)).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(Format.bytes(tree.size(of: id))).font(.callout.monospacedDigit())
                Button("Afficher dans le Finder") { model.revealInFinder(id) }
                Button("Coup d'œil") { quickLookURL = model.url(of: id) }
            } else {
                Text("Clic : sélectionner · double-clic : entrer dans un dossier · ⌘↑ : remonter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }
}
```

- [ ] **Étape 2 : remplacer CarteView**

`Sources/StorageMonitor/Views/Carte/CarteView.swift` :

```swift
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
```

- [ ] **Étape 3 : compiler et tester**

Lance : `perl -e 'alarm 400; exec @ARGV' swift build --product StorageMonitor`, puis `perl -e 'alarm 300; exec @ARGV' swift test`
Résultat attendu : le build se termine sans erreur ni avertissement, puis `✔ Test run with 48 tests passed`.

- [ ] **Étape 4 : vérifier à la main (avec l'utilisateur)**

Lance : `scripts/build-app.sh --install`, puis demande à l'utilisateur d'ouvrir l'app et de vérifier :
1. À la racine, le treemap montre `Users`, `System`, `Applications`… ainsi qu'un bloc gris « Système et autres ». Les couleurs suivent la légende affichée sous la carte.
2. Le survol d'un rectangle affiche une info-bulle avec le nom, la taille, le pourcentage du dossier et la date de modification.
3. Un clic sélectionne l'élément (contour blanc), et la barre du bas affiche son icône, son nom, son chemin et sa taille.
4. Un double-clic sur un dossier y entre et met à jour le fil d'Ariane. Un double-clic sur un fichier ou un paquet ouvre Coup d'œil.
5. Un clic sur un élément du fil d'Ariane remonte jusqu'à ce dossier ; ⌘↑ remonte d'un niveau et sélectionne le dossier qu'on vient de quitter.
6. Avec un élément sélectionné, la barre d'espace ouvre Coup d'œil.
7. Le clic droit propose Afficher dans le Finder, Coup d'œil et Copier le chemin, et chaque action fonctionne.
8. Dans `~/Library/Containers`, le dossier de Docker apparaît (environ 19 Go).
9. **Rafraîchir ce dossier** dans `~/Downloads`, après avoir ajouté un fichier dans le Finder : le fichier apparaît sans rescanner tout le disque.
10. Si le lien « N dossiers inaccessibles » est présent, il ouvre la liste.
11. Les éléments trop petits sont regroupés dans un bloc « N petits éléments ».
12. Lancée sans l'Accès complet au disque (via **Continuer sans**), la carte affiche « Scan partiel », et le lien **Autoriser l'accès…** rouvre l'écran d'accueil.

- [ ] **Étape 5 : commiter**

```bash
git add Sources/StorageMonitor/Views/Carte
git commit -m "feat(app): écran Carte avec treemap interactif" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Couverture de la spec (plan 1/2)

| Spec | Tâches |
|---|---|
| 2. Architecture (modules, protocoles, flux) | 1 à 9. Les protocoles de corbeille, de Docker et de Spotlight arrivent avec le plan 2/2. |
| 3. Scanner : périmètre, mesures, performance, progression, persistance, inaccessibles | 5, 6, 7, 8 ; 9 (persistance automatique, rafraîchir un dossier) |
| 5. Barre latérale et jauge d'espace libre | 9 |
| 5.1 Carte | 4, 11 |
| 5.4 Accès complet au disque | 8, 9, 10 |
| 7. Erreurs du scan et de la persistance | 6, 7, 9 |
| 8. Build, signature, installation | 10 |
| 9. Tests de Scanner, FileTree, Treemap et Persistence | 2 à 8 |
| 10. Critères 1, 2 et 6 | 6 et 9 (n° 1), 11 (n° 2), 10 (n° 6) |
| 4, 5.2, 5.3, 6, critères 3 à 5 | **plan 2/2** (suggestions, doublons, panier, nettoyage) |
