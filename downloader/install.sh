#!/bin/bash
# 最新版をビルドして /Applications に登録(上書きインストール)する。
#   使い方: ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Downloader"
SRC="dist/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

# まず最新の .app をビルド。
./build_app.sh

echo "▶ /Applications に登録中…"
rm -rf "${DEST}"
cp -R "${SRC}" "${DEST}"

# Launch Services に新バージョンを認識させ、アイコンキャッシュを更新。
touch "${DEST}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "${DEST}" >/dev/null 2>&1 || true

echo "✅ インストール完了: ${DEST}"
echo "   メニューバーに常駐します(Dock アイコンはありません)。Launchpad や Spotlight からも起動できます。"
echo "   旧 YouTube-downloader.app / Torrent-downloader.app が /Applications に残っている場合は、"
echo "   magnet: リンクの登録が競合しないよう手動で削除してください。"
