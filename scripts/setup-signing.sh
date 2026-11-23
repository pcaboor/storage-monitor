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
