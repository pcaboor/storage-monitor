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
