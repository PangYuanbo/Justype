#!/bin/bash
# Ensures a stable self-signed code-signing certificate exists in the user's
# login keychain. Used so that rebuilds of JustType keep the same Designated
# Requirement, which means macOS TCC (Accessibility, etc.) preserves grants
# across rebuilds instead of re-prompting every time.
set -euo pipefail

NAME="${1:-JustType Local Sign}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""; then
    echo "✓ Code-signing identity already exists: $NAME"
    exit 0
fi

echo "→ Creating self-signed code-signing identity: $NAME"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Generate self-signed cert with code-signing EKU.
openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    >/dev/null 2>&1

# Bundle key + cert into PKCS#12 for `security import`. Notes:
#  - Force legacy 3DES; modern OpenSSL defaults to AES-256, which macOS
#    `security` can't decrypt.
#  - Use a non-empty password — recent macOS `security import` rejects
#    PKCS#12 with empty passwords ("user name or passphrase…not correct").
P12_PASS="justype-local"
openssl pkcs12 -export \
    -out "$TMP/cert.p12" \
    -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" \
    -name "$NAME" \
    -passout "pass:$P12_PASS" \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg sha1 \
    >/dev/null 2>&1

# Import into login keychain. -T whitelists codesign as an allowed accessor;
# user may still see one "always allow" prompt the first time codesign runs.
security import "$TMP/cert.p12" \
    -k "$KEYCHAIN" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -t cert \
    -f pkcs12 \
    >/dev/null

echo "✓ Imported '$NAME' into login keychain."
echo
echo "  Next steps (one time):"
echo "  1. The first 'codesign' run after this may prompt for keychain access —"
echo "     click 'Always Allow' so future builds don't re-prompt."
echo "  2. Re-grant Accessibility for JustType once in System Settings →"
echo "     Privacy & Security → Accessibility."
echo "  3. From then on, rebuilds preserve the permission."
