#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain.
#
# Why this matters: an ad-hoc signature's designated requirement is the code
# hash itself, so it changes on every build. macOS then treats each rebuild as
# a different app and silently drops its TCC permissions — you grant
# Accessibility, rebuild, and the running app is refused while System Settings
# still shows the checkbox ticked.
#
# Signing with a certificate makes the designated requirement
#   identifier "com.example.app" and certificate root = H"…"
# which is identical across rebuilds, so permissions survive.
#
# This is for local development. Distribution still needs a Developer ID —
# see docs/SIGNING.md.
set -euo pipefail

NAME="${1:-Mac Utilities Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity | grep -q "$NAME"; then
  echo "Identity '$NAME' already exists."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > ext.cnf <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3

[dn]
CN = $NAME
O  = Mac Utilities
C  = US

[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
1.2.840.113635.100.6.1.13 = critical,DER:05:00
EOF

echo "==> Generating certificate"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout key.pem -out cert.pem -days 3650 -config ext.cnf 2>/dev/null

# Apple's Security framework rejects OpenSSL 3's default PKCS12 MAC and PBE,
# so the legacy encoding is required here.
openssl pkcs12 -export -inkey key.pem -in cert.pem \
  -out bundle.p12 -name "$NAME" \
  -legacy -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES \
  -passout pass:temp 2>/dev/null

echo "==> Importing into the login keychain"
security import bundle.p12 -k "$KEYCHAIN" -P temp -A

echo "==> Done"
security find-identity | grep "$NAME" || true
echo
echo "The certificate is untrusted for verification (CSSMERR_TP_NOT_TRUSTED),"
echo "which is expected and does not prevent signing. Gatekeeper will still"
echo "warn on first launch; the point is that TCC permissions now persist."
