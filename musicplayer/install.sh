#!/bin/bash
# 最新版をビルドして /Applications に登録(上書きインストール)する。
#   使い方: ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MusicPlayer"
SRC="dist/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

./build_app.sh

echo "▶ /Applications に登録中…"
rm -rf "${DEST}"
cp -R "${SRC}" "${DEST}"

touch "${DEST}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "${DEST}" >/dev/null 2>&1 || true

echo "✅ インストール完了: ${DEST}"
