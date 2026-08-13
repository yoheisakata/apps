#!/bin/bash
# 最新版をビルドして /Applications/MyApplications に登録（上書きインストール）する。
#   使い方: ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MyNetWorth"
SRC="${APP_NAME}.app"
INSTALL_DIR="/Applications/MyApplications"
DEST="${INSTALL_DIR}/${APP_NAME}.app"

# まず最新の .app をビルド。
./build_app.sh

echo "▶ /Applications/MyApplications に登録中…"
mkdir -p "${INSTALL_DIR}"
rm -rf "${DEST}"
cp -R "${SRC}" "${DEST}"

# Launch Services に新バージョンを認識させ、アイコンキャッシュを更新。
touch "${DEST}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "${DEST}" >/dev/null 2>&1 || true

echo "✅ インストール完了: ${DEST}"
echo "   Launchpad や Spotlight から「${APP_NAME}」で起動できます。"
