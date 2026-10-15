#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="${1:-$ROOT_DIR/UsageBar.app}"
SIGNING_IDENTITY="${USAGEBAR_CODESIGN_IDENTITY:-UsageBar Local Signing}"

if [[ ! -f "$APP_DIR/Contents/MacOS/UsageBar" ]]; then
  print -u2 "UsageBar 앱 번들을 찾을 수 없습니다: $APP_DIR"
  exit 1
fi

PREVIOUS_REQUIREMENT="$(codesign -d -r- "$APP_DIR" 2>&1 | sed -E -n 's/^(# )?designated => //p' || true)"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  if [[ "${USAGEBAR_ALLOW_ADHOC_SIGNING:-0}" != "1" ]]; then
    print -u2 "임시 서명은 업데이트 후 키체인 허용을 유지하지 못합니다. 테스트용으로 명시적으로 허용해야 합니다."
    exit 1
  fi
  codesign --force --sign - "$APP_DIR"
else
  # Use one cryptographic signer and bundle identifier across all local updates.
  # Do not fall back to ad-hoc signing when the private key is missing or locked.
  codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"
REQUIREMENT="$(codesign -d -r- "$APP_DIR" 2>&1 | sed -E -n 's/^(# )?designated => //p')"
if [[ "$SIGNING_IDENTITY" != "-" && ( -z "$REQUIREMENT" || "$REQUIREMENT" == cdhash* ) ]]; then
  print -u2 "업데이트 간 유지되는 인증서 기반 앱 식별자를 확인하지 못했습니다. 설치하지 마세요."
  exit 1
fi
if [[ "$SIGNING_IDENTITY" != "-" && -n "$PREVIOUS_REQUIREMENT" && "$PREVIOUS_REQUIREMENT" != cdhash* ]]; then
  if ! codesign --verify --strict -R "=$PREVIOUS_REQUIREMENT" "$APP_DIR"; then
    print -u2 "이전 버전과 서명 신원이 다릅니다. 기존 허용을 유지할 수 없으므로 설치하지 마세요."
    exit 1
  fi
fi
print "서명 확인: $REQUIREMENT"
