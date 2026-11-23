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
