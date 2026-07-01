#!/bin/bash
# CleanMac をビルドして /Applications にインストールする。
#   ./install.sh          → ビルド → /Applications へコピー → 起動
# インストール後は Launchpad / Finder のアプリケーションからダブルクリックで起動できる。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=CleanMac
APP_BUNDLE="${APP_NAME}.app"
DEST_DIR="/Applications"
DEST="${DEST_DIR}/${APP_BUNDLE}"

# 1. .app バンドルを作成（署名込み）
./build_app.sh

# 2. /Applications へコピー（既存があれば置き換え）
echo "==> ${DEST} にインストール"
if [[ -e "${DEST}" ]]; then
    rm -rf "${DEST}"
fi

if cp -R "${APP_BUNDLE}" "${DEST_DIR}/" 2>/dev/null; then
    echo "    コピー完了"
else
    echo "    権限が必要です。sudo でコピーします（パスワードを求められます）"
    sudo cp -R "${APP_BUNDLE}" "${DEST_DIR}/"
fi

echo "==> インストール完了: ${DEST}"
echo "    Launchpad か アプリケーションフォルダから CleanMac を起動できます。"

# 3. 起動して確認
open "${DEST}"
