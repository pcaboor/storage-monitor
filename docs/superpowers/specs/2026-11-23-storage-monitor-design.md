# Storage Monitor : spécification de conception

- **Date :** 2026-11-23
- **Statut :** validée en brainstorming, en attente de relecture

## 1. Contexte et objectif

Une app macOS personnelle, inspirée du module *Space Lens* de CleanMyMac. Elle doit :

1. **cartographier** l'occupation de tout le disque sous forme de treemap navigable ;
2. **suggérer** ce qui peut être supprimé sans effort de réflexion ;
3. **nettoyer** simplement et de façon sûre, via un panier.

**Situation de départ :** 228 Go de disque, environ 16 Go libres. Docker occupe à lui seul 19 Go (`~/Library/Containers/com.docker.docker`), auxquels s'ajoutent les caches (environ 4,5 Go), les Téléchargements (3,8 Go) et plus de 20 dossiers `node_modules`.

### Décisions prises

| Sujet | Décision |
|---|---|
| Public | Usage personnel uniquement : ni notarisation, ni App Store, ni sandbox |
| Mode de tri | Carte explorable **et** suggestions automatiques |
| Périmètre du scan | Tout le disque (`/`), avec « Accès complet au disque » |
| Suppression | Corbeille par défaut, suppression définitive possible pour les éléments 🟢 uniquement |
| Visualisation | Treemap (rectangles imbriqués) |
| Catégories de suggestions | Caches, Dev, Docker, Installeurs, Gros fichiers dormants, Doublons, Logs |
| Organisation de la fenêtre | Barre latérale à trois écrans : Carte, Suggestions, Panier |
| Fonctionnement | Uniquement à la demande, le dernier scan est conservé |
| Technologie | SwiftUI natif, compilé avec SwiftPM et les Command Line Tools (Xcode n'est pas installé) |
| Langue de l'interface | Français |

### Hors périmètre (v1)

- Surveillance en arrière-plan, icône dans la barre des menus, notifications.
- Sauvegardes iPhone/iPad, pièces jointes Mail, applications inutilisées.
- Suppression d'éléments qui exigent les droits administrateur (pas de demande de mot de passe).
- Scan des disques externes et des volumes réseau.
- Malware, « optimisation », désinstallateur d'applications.
- Tests automatisés de l'interface.

## 2. Architecture

```
storage-monitor/
├── Package.swift                 (swift-tools-version 6.0, macOS 14 minimum)
├── Sources/
│   ├── StorageCore/              bibliothèque, aucune dépendance à SwiftUI
│   │   ├── Scan/
│   │   ├── Model/
│   │   ├── Treemap/
│   │   ├── Suggestions/
│   │   ├── Cleanup/
│   │   └── Persistence/
│   └── StorageMonitor/           exécutable SwiftUI (vues et view models légers)
├── Tests/StorageCoreTests/       swift-testing
└── scripts/
    ├── setup-signing.sh
    └── build-app.sh
```

| Module | Responsabilité | Interface |
|---|---|---|
| **Scan** | Parcourt le système de fichiers et publie sa progression ; annulable | `scan(root:) async throws -> FileTree`, plus un flux de `ScanProgress` |
| **Model** | `FileTree` : stockage compact (tableaux et index parents, pas un objet par nœud) de 2 à 3 millions d'entrées, avec les tailles cumulées par dossier | Requêtes : enfants, chemin, taille, type dominant ; mutation : `remove(nodes:)` |
| **Treemap** | Algorithme *squarified* ; fonction pure | `layout(sizes:in:) -> [CGRect]` |
| **Suggestions** | Une `Rule` par catégorie, suivie d'une passe de déduplication | `FileTree -> [Suggestion]` |
| **Cleanup** | `CleanupPlan` (regroupements, totaux, choix de méthode) et `Cleaner` (exécution, garde-fous, journal) | `[CartItem] -> CleanupPlan -> CleanupReport` |
| **Persistence** | Sauvegarde et chargement du dernier scan au format binaire versionné | `save(FileTree)`, `load() -> FileTree?` |

Les dépendances externes (corbeille, appels à `docker`, Spotlight, date courante) passent par des **protocoles**, ce qui permet de les remplacer par des versions simulées dans les tests.

**Flux :** Scan → `FileTree` → (Treemap + Suggestions) → l'utilisateur remplit le panier → `CleanupPlan` → `Cleaner` → `FileTree.remove` → Persistence.

Emplacement des données : `~/Library/Application Support/StorageMonitor/` (`last-scan.bin`, `cleanup-log.jsonl`).

## 3. Scanner

### Périmètre

- Le scan part de `/`.
- Il **ignore** `/System/Volumes/*` : le contenu du volume Data est déjà visible via les firmlinks (`/Users`, `/Applications`, `/private`…), le parcourir compterait tout deux fois.
- Il **ignore** `/Volumes/*`, `/dev`, les montages réseau et tout autre volume que celui de départ.
- Il **ne suit pas** les liens symboliques.
- **Bloc « Système et autres »** = espace utilisé du volume − total scanné. Il couvre les snapshots locaux, le swap et le purgeable, et permet de retrouver le total affiché par Réglages Système.

### Données collectées par entrée

Nom, index du parent, **taille allouée sur le disque** (et non la taille logique), date de modification, type (fichier, dossier ou bundle), indicateur « partage des blocs » (clone APFS) lorsqu'il est disponible.

### Règles de mesure

- **Taille allouée** : les fichiers creux, comme `Docker.raw`, sont comptés à leur taille réelle.
- **Liens physiques** : si `nlink > 1`, le fichier n'est compté qu'une fois, grâce à un ensemble d'identifiants (périphérique, inode).
- **Bundles** (`.app`, `.photoslibrary`, et tout paquet reconnu par le Finder) : un seul nœud feuille avec sa taille totale. On ne peut pas y entrer.
- **Clones APFS** : pas de dédoublonnage. Limite assumée et affichée dans le panier : la place libérée peut être inférieure à la taille indiquée.

### Performance

- Lecture par lots avec `getattrlistbulk`.
- Parallélisme sur les sous-dossiers, limité à 8 tâches concurrentes.
- Objectif : moins de 2 minutes pour environ 2 millions d'entrées sur le SSD interne.

### Progression et annulation

- L'app publie environ 10 fois par seconde le nombre d'entrées, les octets comptés et le dossier en cours.
- En cas d'annulation, l'arbre partiel est abandonné et le scan précédent conservé.

### Dossiers inaccessibles

Ils sont comptés et leur liste est consultable. Si l'Accès complet au disque n'est pas accordé (test de l'écran 5.4), la carte porte la mention « scan partiel » et propose d'ouvrir cet écran.

### Persistance

- Un scan complet est sauvegardé automatiquement.
- Au lancement, l'app affiche le dernier scan avec sa date.
- Deux actions : **Rescanner tout** et **Rafraîchir ce dossier**. Cette dernière rescanne un sous-arbre et le remplace dans le `FileTree`, puis les totaux des dossiers parents sont recalculés.

## 4. Moteur de suggestions

Une `Suggestion` contient : catégorie, chemins (un ou plusieurs nœuds), taille, explication courte, niveau de risque, méthodes de nettoyage autorisées.

- 🟢 **Sans risque** (se régénère tout seul) : corbeille, ou suppression définitive si l'interrupteur du panier est activé.
- 🟠 **À vérifier** : corbeille uniquement.

| # | Catégorie | Détection | Risque |
|---|---|---|---|
| 1 | **Caches** | Chaque sous-dossier direct de `~/Library/Caches` et de `~/.cache`, avec le nom de l'app retrouvé à partir de l'identifiant de bundle. Les caches des apps en cours d'exécution (`NSWorkspace.runningApplications`) sont signalés et **décochés** par défaut. | 🟢 |
| 2 | **Dev** | `node_modules` situé à côté d'un `package.json` (seulement le plus haut, pas les imbriqués) ; `target/` à côté d'un `Cargo.toml` ; `~/Library/Developer/Xcode/DerivedData` ; caches npm (`~/.npm/_cacache`), yarn, pnpm, pip, Homebrew et Gradle. L'app affiche la date de dernière modification du projet. | 🟢 |
| 3 | **Docker** | Si le binaire est trouvé et le démon répond, l'app lit `docker system df` et propose : images inutilisées, conteneurs arrêtés et cache de build (🟢) ; volumes orphelins (🟠). Sinon, elle affiche une suggestion informative « Lance Docker Desktop pour analyser », avec la taille du dossier Docker. | 🟢/🟠 |
| 4 | **Installeurs** | Fichiers `.dmg`, `.pkg`, `.xip` et `.iso` de plus de 7 jours dans `~/Downloads` et `~/Desktop`. | 🟠 |
| 5 | **Gros fichiers dormants** | Fichiers de plus de 500 Mo non ouverts depuis plus de 6 mois. La date vient de `kMDItemLastUsedDate` (Spotlight) quand elle existe, sinon de la date de modification. La recherche couvre `~` **hors** `~/Library` et ignore les bundles. | 🟠 |
| 6 | **Doublons** | Lancement **à la demande** uniquement. Fichiers de plus de 1 Mo dans `~` hors `~/Library`, bundles exclus. Trois étapes : regroupement par taille, puis empreinte du premier et du dernier bloc de 64 Ko, puis SHA-256 complet (CryptoKit). Les clones APFS sont exclus. La copie dont la date de création est la plus ancienne est conservée par défaut. | 🟠 |
| 7 | **Logs** | Fichiers de plus de 7 jours dans `~/Library/Logs`, y compris `DiagnosticReports`. | 🟢 |

### Règles transversales

- **Déduplication.** Un chemin n'appartient qu'à une seule suggestion. Priorité : Dev > Docker > Caches > Logs > Installeurs > Doublons > Gros fichiers. Si un dossier est suggéré, aucun de ses descendants ne l'est.
- **Droits administrateur.** Un élément que l'utilisateur ne peut pas supprimer (propriétaire `root` ou dossier parent non modifiable) est affiché **grisé**, avec la mention « nécessite les droits administrateur ». On ne peut pas le sélectionner.

## 5. Interface

La fenêtre est une `NavigationSplitView` avec une barre latérale de trois entrées : 🗺 Carte, ✨ Suggestions, 🧺 Panier.

En bas de la barre latérale :
- une jauge « Libre : X Go sur Y Go », lue sur les capacités du volume et rafraîchie après chaque nettoyage ;
- un badge sur l'entrée Panier, avec le nombre d'éléments et la taille.

### 5.1 Carte

**Barre d'outils :** fil d'Ariane cliquable, retour (⌘↑), **Rescanner tout**, **Rafraîchir ce dossier**.

**Treemap du dossier courant :**
- Deux niveaux de profondeur, dessinés avec le `Canvas` de SwiftUI.
- **Couleur = type de contenu** : vidéos, images, audio, code, apps, archives, documents, système, autres. Un dossier prend la couleur de son type dominant en octets. Une légende est affichée.
- Les éléments trop petits pour être dessinés (moins de 4 × 4 pt) sont regroupés dans un bloc « N petits éléments ».
- ✨ marque les éléments suggérés ; des hachures marquent ceux présents dans le panier.

**Interactions :**
- **Survol** : info-bulle avec le nom, la taille, le pourcentage du parent et la date de modification.
- **Clic** : sélection. La barre d'infos en bas propose **Afficher dans le Finder**, **Coup d'œil** (barre d'espace, via QuickLook) et **Ajouter au panier**.
- **Double-clic** : entre dans le dossier. Sur un bundle ou un fichier, ouvre Coup d'œil.
- **Clic droit** : les mêmes actions, plus **Copier le chemin**.

**Scan en cours :** progression (entrées, octets, dossier courant) et bouton **Annuler**.

### 5.2 Suggestions

- En-tête « X Go récupérables », ainsi qu'un bouton **Chercher les doublons** tant que cette recherche n'a pas été lancée.
- Une carte repliable par catégorie, avec son total.
- Chaque ligne affiche : case à cocher, nom et chemin raccourci, taille, badge 🟢/🟠, explication, lien **Voir sur la carte** (bascule vers Carte, navigue jusqu'au parent et surligne l'élément).
- Bouton **Ajouter au panier** pour les éléments cochés.
- Pour les doublons, chaque groupe liste ses copies avec un choix « garder celle-ci ».

### 5.3 Panier

- Éléments groupés par méthode : **Vers la corbeille**, **Suppression définitive**, **Commandes Docker**. On peut retirer chaque élément individuellement.
- Interrupteur **Supprimer définitivement les éléments sans risque**, désactivé par défaut. Il ne fait basculer que les éléments 🟢.
- Espace libéré estimé, avec la note sur les clones APFS.
- **Nettoyer…** ouvre une feuille de confirmation qui récapitule chaque groupe. Le bouton destructif est rouge et indique le montant (« Supprimer définitivement 12 Go »).
- Encart **Corbeille** : taille de `~/.Trash` et bouton **Vider la corbeille**, avec confirmation.
- Après le nettoyage, un rapport indique les octets libérés, avec la variation réelle de l'espace libre du volume, et la liste des échecs avec leur raison.

### 5.4 Écran « Accès complet au disque »

- **Détection** : l'app tente de lire un emplacement protégé par TCC, comme `~/Library/Safari` ou `~/Library/Mail`.
- **Sans accès** : une explication et trois boutons : **Ouvrir les Réglages** (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`), **Vérifier à nouveau** et **Continuer sans**. Dans ce dernier cas, la carte indique « scan partiel ».

## 6. Nettoyage

### Méthodes

- **Corbeille** : `FileManager.trashItem(at:resultingItemURL:)`.
- **Définitive** : `FileManager.removeItem(at:)`. Un lien symbolique est supprimé lui-même, jamais sa cible.
- **Docker** : `docker image prune -a -f`, `docker container prune -f`, `docker builder prune -f`, et `docker volume prune -f` si cette option est cochée. Le binaire est cherché dans `/usr/local/bin`, `/opt/homebrew/bin` et `/Applications/Docker.app/Contents/Resources/bin`. Le gain est mesuré avec `docker system df` avant et après. Le rapport indique que Docker Desktop réduit son fichier disque progressivement.
- **Vider la corbeille** : suppression directe du contenu de `~/.Trash`, ce qui nécessite l'Accès complet au disque.

### Garde-fous, vérifiés pour chaque élément juste avant d'agir

1. **Liste noire de chemins**, en comparant le chemin exact une fois normalisé : `/`, `/System`, `/usr`, `/bin`, `/sbin`, `/private`, `/Library`, `/Applications`, `/Users`, `~`, `~/Library`, `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`. Ces dossiers eux-mêmes ne sont jamais supprimés ; leur contenu peut l'être.
2. **L'élément existe toujours** et sa taille allouée n'a pas significativement changé depuis le scan. Si l'écart dépasse **à la fois** 10 % et 10 Mo, l'élément est **ignoré** avec la mention « modifié depuis le scan ».
3. **Exécution séquentielle**, annulable entre deux éléments.

### Journal

Chaque action ajoute une ligne à `cleanup-log.jsonl` : date, chemin, taille, méthode, résultat et erreur éventuelle.

### Après le nettoyage

Les nœuds supprimés sont retirés du `FileTree` et les totaux des dossiers parents recalculés. L'espace libre est relu et le scan sauvegardé.

## 7. Gestion des erreurs

| Situation | Comportement |
|---|---|
| Permission refusée ou fichier occupé pendant le nettoyage | L'élément est conservé ; l'échec et sa raison figurent dans le rapport |
| Démon Docker injoignable | Les commandes Docker sont marquées en échec, le reste du panier continue |
| Dossier illisible pendant le scan | Il est compté et listé, le scan continue |
| Scan annulé ou en erreur | Le scan précédent est conservé, rien n'est enregistré |
| `last-scan.bin` illisible ou d'une autre version | Il est ignoré, l'app propose un nouveau scan |
| Pas d'Accès complet au disque | Écran 5.4 ; un scan partiel reste possible |

## 8. Build, signature et installation

- **`scripts/setup-signing.sh`**, à lancer une fois : crée un certificat auto-signé de signature de code, « Storage Monitor Local », dans le trousseau de session. Sans lui, macOS oublierait l'autorisation d'accès au disque à chaque recompilation : une signature ad hoc change d'empreinte à chaque build, alors qu'un certificat stable garde la même *designated requirement*.
- **`scripts/build-app.sh [--install]`** :
  1. `swift build -c release` ;
  2. assemblage de `build/Storage Monitor.app` (`Contents/MacOS`, `Info.plist` avec l'identifiant `local.storage-monitor` et `LSMinimumSystemVersion` = 14.0) ;
  3. signature avec `codesign --sign "Storage Monitor Local"` ;
  4. avec `--install`, copie dans `~/Applications`.
- **`.gitignore`** : `.build/`, `build/`, `.superpowers/`.

Faisabilité vérifiée : un paquet SwiftPM avec SwiftUI et `Canvas` compile, et `swift test` s'exécute avec `swift-testing` en n'utilisant que les Command Line Tools (Swift 6.1.2, SDK macOS 15.5).

## 9. Tests

Les tests utilisent `swift-testing` et se lancent avec `swift test`. Ils portent tous sur `StorageCore`.

| Sujet | Cas testés |
|---|---|
| Scanner | Arborescence temporaire : tailles connues, lien physique compté une fois, lien symbolique non suivi, fichier creux compté à sa taille allouée, dossier illisible compté, bundle traité comme une feuille, annulation |
| FileTree | Agrégats des dossiers, `remove(nodes:)` et recalcul des parents, remplacement d'un sous-arbre, type dominant |
| Treemap | Couverture totale, absence de chevauchement, aires proportionnelles (tolérance de 1 %), tailles nulles, élément unique |
| Règles 1 à 7 | Arbres de test donnant les suggestions attendues ; priorités et déduplication entre catégories ; éléments non supprimables grisés |
| Doublons | Fichiers identiques, différents, ou de même taille avec un contenu différent ; choix de la copie conservée |
| CleanupPlan | Regroupement par méthode, totaux, interrupteur 🟢, refus de la suppression définitive pour 🟠 |
| Cleaner | Dossier temporaire, corbeille et Docker simulés : succès, liste noire, « modifié depuis le scan », lien symbolique, annulation, lignes du journal |
| Persistence | Un aller-retour enregistrement/chargement donne un arbre identique ; un fichier corrompu ou d'une autre version est rejeté |

L'interface est vérifiée à la main en lançant l'app : scan complet, navigation dans la carte, ajout au panier, nettoyage réel d'un cache.

## 10. Critères de réussite

1. Un scan complet de `/` se termine en moins de 2 minutes, et le total (scanné + « Système et autres ») correspond à l'espace utilisé du volume.
2. La carte permet de descendre jusqu'à n'importe quel gros dossier en quelques double-clics, avec un affichage fluide.
3. Les suggestions font apparaître au moins Docker, les caches et les `node_modules` du Mac actuel.
4. Un nettoyage via le panier libère réellement l'espace annoncé, à l'exception des clones et de Docker, dont la réduction est progressive, et le journal le trace.
5. Aucun chemin de la liste noire ne peut être supprimé, ce que les tests prouvent.
6. L'autorisation d'accès au disque survit à une recompilation.
