#!/bin/zsh
set -euo pipefail
umask 077

ROOT_DIR="${0:A:h:h}"
SIGNING_NAME="UsageBar Local Signing"
SIGNING_KEYCHAIN="$(security default-keychain -d user | sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/')"

if [[ -z "$SIGNING_KEYCHAIN" || ! -f "$SIGNING_KEYCHAIN" ]]; then
  print -u2 "사용자 기본 키체인을 찾을 수 없습니다."
  exit 1
fi

# Never rotate an existing signer silently: its certificate is the app's identity.
if security find-certificate -c "$SIGNING_NAME" "$SIGNING_KEYCHAIN" >/dev/null 2>&1; then
  print "기존 $SIGNING_NAME 인증서를 유지합니다."
  exit 0
fi

SIGNING_TEMP_DIR="$(mktemp -d /private/tmp/usagebar-signing.XXXXXXXX)"
cleanup() {
  # Only the generated transport files, never user keys or Keychain contents.
  rm -f "$SIGNING_TEMP_DIR/private-key.pem" "$SIGNING_TEMP_DIR/certificate.pem" "$SIGNING_TEMP_DIR/identity.p12"
  rmdir "$SIGNING_TEMP_DIR"
}
trap cleanup EXIT

# The temporary transport files are owner-only and removed on exit. Some macOS
# versions reject empty PKCS#12 passphrases, so use a fresh transport-only secret.
# The imported key is non-exportable and grants signing access only to codesign.
export USAGEBAR_SIGNING_TRANSFER_PASSWORD="$(/usr/bin/openssl rand -hex 32)"
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
  -config "$ROOT_DIR/scripts/local-signing.cnf" \
  -keyout "$SIGNING_TEMP_DIR/private-key.pem" -out "$SIGNING_TEMP_DIR/certificate.pem"
/usr/bin/openssl pkcs12 -export -name "$SIGNING_NAME" \
  -inkey "$SIGNING_TEMP_DIR/private-key.pem" -in "$SIGNING_TEMP_DIR/certificate.pem" \
  -out "$SIGNING_TEMP_DIR/identity.p12" -descert -macalg sha1 \
  -passout env:USAGEBAR_SIGNING_TRANSFER_PASSWORD
security import "$SIGNING_TEMP_DIR/identity.p12" -k "$SIGNING_KEYCHAIN" \
  -f pkcs12 -P "$USAGEBAR_SIGNING_TRANSFER_PASSWORD" -x -T /usr/bin/codesign
unset USAGEBAR_SIGNING_TRANSFER_PASSWORD

# No system/user trust-root changes, Claude ACL changes, or credential exports.
print "$SIGNING_NAME 인증서를 사용자 키체인에 등록했습니다."
