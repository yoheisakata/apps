#!/bin/bash
# Renamer.app を Apple Silicon (arm64) ネイティブでビルドする
set -euo pipefail
cd "$(dirname "$0")"

APP="Renamer.app"

# アイコンがなければ生成する。
if [ ! -f AppIcon.icns ]; then
  swift make-icon.swift
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library \
  -target arm64-apple-macos13.0 \
  Sources/main.swift \
  -o "$APP/Contents/MacOS/Renamer"

cp Info.plist "$APP/Contents/"
cp AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign - "$APP"

echo "ビルド完了: $(pwd)/$APP"
