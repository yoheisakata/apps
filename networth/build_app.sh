#!/bin/bash
# NetWorth を .app バンドルとしてビルドする。
#   ./build_app.sh          → release ビルドして NetWorth.app を生成
#   open NetWorth.app       → 起動
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
APP_NAME=NetWorth
APP_BUNDLE="${APP_NAME}.app"

# アイコンがなければ生成する。
if [[ ! -f AppIcon.icns ]]; then
    swift make-icon.swift
fi

echo "==> swift build (${CONFIG})"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "ビルド成果物が見つかりません: ${BIN_PATH}" >&2
    exit 1
fi

echo "==> ${APP_BUNDLE} を作成"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"

# バージョンは Main.swift の appVersion が唯一の定義。Info.plist に反映する。
VERSION=$(sed -n 's/^let appVersion = "\(.*\)"$/\1/p' Sources/NetWorth/Main.swift)
if [[ -n "${VERSION}" ]]; then
    plutil -replace CFBundleShortVersionString -string "${VERSION}" \
        "${APP_BUNDLE}/Contents/Info.plist"
    echo "==> バージョン: ${VERSION}"
fi
if [[ -f AppIcon.icns ]]; then
    cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# ダブルクリックで確実に起動できるようアドホック署名する
echo "==> アドホック署名"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> 完了: ${APP_BUNDLE}"
echo "    起動: open ${APP_BUNDLE}"
