#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="RetroGames"
SRC="${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

./build_app.sh

echo "▶ /Applications に登録中…"
rm -rf "${DEST}"
cp -R "${SRC}" "${DEST}"
touch "${DEST}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "${DEST}" >/dev/null 2>&1 || true

echo "✅ インストール完了: ${DEST}"
