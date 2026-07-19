#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="RetroGames"
SRC="${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

./build_app.sh

# 起動中の古いインスタンスが残っていると新バイナリが反映されないため終了させる
if pgrep -f "${APP_NAME}.app/Contents/MacOS" >/dev/null 2>&1; then
    echo "▶ 起動中の ${APP_NAME} を終了中…"
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || \
        pkill -f "${APP_NAME}.app/Contents/MacOS" || true
    sleep 1
fi

echo "▶ /Applications に登録中…"
rm -rf "${DEST}"
cp -R "${SRC}" "${DEST}"
touch "${DEST}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "${DEST}" >/dev/null 2>&1 || true

echo "✅ インストール完了: ${DEST}"
