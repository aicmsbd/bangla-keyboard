#!/usr/bin/env bash
# One-time: create a STABLE self-signed code-signing identity for বাঙলা কিবোর্ড.app.
#
# Why: an ad-hoc signature (`codesign --sign -`) has a Designated Requirement that is a
# bare cdhash, which changes on EVERY rebuild — so macOS's Accessibility (TCC) grant,
# which pins to that requirement, silently stops matching after each build and the
# system-wide keyboard hook goes dead. A self-signed cert gives a cdhash-INDEPENDENT
# requirement (identifier + certificate leaf hash), so ONE Accessibility grant survives
# all future rebuilds.
#
# This is fully non-interactive: the cert lives in a DEDICATED keychain with a known
# password, and `set-key-partition-list` pre-authorises codesign so no GUI password prompt
# appears. It does NOT touch your login keychain and does NOT add any system trust
# (`add-trusted-cert` is intentionally NOT used — TCC matches the embedded leaf-cert hash
# without it).
#
# SECURITY — treat the PRIVATE KEY as sensitive. TCC binds the app's system-wide
# Accessibility (keystroke-tap) grant to this cert's leaf hash + bundle id, so whoever holds
# the key could sign a look-alike binary that inherits that grant with no new user prompt.
# For per-developer local builds the key is freshly generated and unique to your machine
# (low risk). For CI/release, keep the exported key in ENCRYPTED secrets only, with a strong
# random export password (see --export). Remove everything with:  ./setup-signing.sh --remove
set -euo pipefail

SIGN_ID_CN="Bangla Keyboard Dev"
KC_NAME="bangla-keyboard-signing"
KC="$HOME/Library/Keychains/${KC_NAME}.keychain-db"
KC_PASS="banglakeyboard-local-signing"        # not a secret — signs only this local app

# Export the identity as a base64 PKCS12 for a GitHub Actions secret, so CI release builds
# sign with the SAME cert (grants persist for end users across releases). Prints the two
# secret values. Usage:  ./setup-signing.sh --export
if [ "${1:-}" = "--export" ]; then
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  EXP_PW="$(openssl rand -hex 24)"    # strong random p12 password — store it as the secret below
  if ! security export -k "$KC" -t identities -f pkcs12 -P "$EXP_PW" -o "$T/id.p12" >/dev/null 2>&1; then
    echo "export failed — run ./setup-signing.sh first to create the identity." >&2; exit 1
  fi
  echo "# --- add these as GitHub Actions repository secrets ---"
  echo "MACOS_SIGN_P12_PASSWORD = $EXP_PW"
  echo "MACOS_SIGN_P12_BASE64 = (single line below)"
  base64 < "$T/id.p12" | tr -d '\n'; echo
  exit 0
fi

if [ "${1:-}" = "--remove" ]; then
  security list-keychains -d user -s $(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//' | grep -v "$KC_NAME" | tr '\n' ' ') 2>/dev/null || true
  security delete-keychain "$KC" 2>/dev/null && echo "Removed signing keychain." || echo "Nothing to remove."
  exit 0
fi

# Idempotent: if the identity already exists, do NOTHING — regenerating would mint a new
# leaf hash and break the persisted Accessibility grant. (Use plain find-identity, not
# `-v`: a self-signed cert is untrusted so `-v` never lists it, but codesign signs with
# it fine and TCC pins to its stable leaf hash regardless of trust.)
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID_CN"; then
  echo "Signing identity '$SIGN_ID_CN' already present — nothing to do."
  exit 0
fi

echo "==> creating dedicated signing keychain: $KC"
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings "$KC"                       # no auto-lock timeout
security unlock-keychain -p "$KC_PASS" "$KC"

echo "==> generating self-signed code-signing certificate (CN=$SIGN_ID_CN)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/req.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = Bangla Keyboard Dev
[ v3 ]
basicConstraints = critical,CA:false
keyUsage         = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/bk.key" -out "$TMP/bk.crt" -config "$TMP/req.cnf" >/dev/null 2>&1
P12_PASS="bk"        # non-empty passphrase (empty breaks macOS PKCS12 MAC verification)
openssl pkcs12 -export -inkey "$TMP/bk.key" -in "$TMP/bk.crt" \
  -name "$SIGN_ID_CN" -out "$TMP/bk.p12" -passout "pass:$P12_PASS" >/dev/null 2>&1

echo "==> importing into the signing keychain (codesign-authorised)"
security import "$TMP/bk.p12" -k "$KC" -P "$P12_PASS" -T /usr/bin/codesign -A >/dev/null 2>&1
# Pre-authorise codesign to use the key with NO GUI prompt (uses the known keychain pw).
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null 2>&1

# Add our keychain to the user search list (keep the existing ones, no duplicates).
EXISTING="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//' | grep -v "$KC_NAME" | tr '\n' ' ')"
security list-keychains -d user -s $EXISTING "$KC" >/dev/null 2>&1

if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID_CN"; then
  echo "==> OK: '$SIGN_ID_CN' is ready (shows as untrusted — that's expected and fine)."
  echo "    build.sh will now sign with it, so the Accessibility grant persists across rebuilds."
else
  echo "==> WARNING: identity not visible to codesign; build.sh will fall back to ad-hoc." >&2
  exit 2
fi
