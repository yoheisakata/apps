#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
APP_NAME=MyGames
DISPLAY_NAME=MyGames
APP_BUNDLE="${DISPLAY_NAME}.app"

if [[ ! -f AppIcon.icns ]]; then
    echo "==> アイコン生成"
    swift make-icon.swift
fi

echo "==> swift build (${CONFIG})"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"

echo "==> ${APP_BUNDLE} を作成"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"

VERSION=$(sed -n 's/^let appVersion = "\(.*\)"$/\1/p' Sources/MyGames/Main.swift)
if [[ -n "${VERSION}" ]]; then
    plutil -replace CFBundleShortVersionString -string "${VERSION}" \
        "${APP_BUNDLE}/Contents/Info.plist"
    echo "==> バージョン: ${VERSION}"
fi

if [[ -f AppIcon.icns ]]; then
    cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# TitleMap のフォールバック用にコピーを同梱する(通常はリポジトリの json を直接読む)。
if [[ -f title-map.json ]]; then
    cp title-map.json "${APP_BUNDLE}/Contents/Resources/"
fi

echo "==> アドホック署名"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> 完了: ${APP_BUNDLE}"
