#!/bin/bash
# MyMusic を Finder からダブルクリックで起動できる .app バンドルに固める。
#   使い方: ./build_app.sh   →  dist/MyMusic.app が生成される
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MyMusic"
EXEC_NAME="MyMusic"
BUNDLE_ID="com.yohei.mymusic"
APP_DIR="dist/${APP_NAME}.app"

echo "▶ アイコンを生成中…"
swift make-icon.swift

echo "▶ リリースビルド中…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${EXEC_NAME}"

echo "▶ .app バンドルを構成中…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${EXEC_NAME}"
cp "AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

# バージョンは Sources/MyMusic/Main.swift の appVersion が唯一の定義。
VERSION=$(sed -n 's/^let appVersion = "\(.*\)"$/\1/p' Sources/MyMusic/Main.swift)
VERSION="${VERSION:-1.0.0}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXEC_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Gatekeeper 警告を抑えるため ad-hoc 署名する。
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true

echo "✅ 完成: ${APP_DIR}"
