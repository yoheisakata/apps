#!/usr/bin/env bash
# build.sh — build the MyGallery app (native Swift macOS local-folder photo browser).
#
# Usage:
#   ./build.sh install   build + copy to /Applications/MyApplications (launch from Spotlight/Launchpad)
#   ./build.sh app       build a double-clickable "MyGallery.app" in build/
#   ./build.sh build     compile the raw binary only
#   ./build.sh clean     remove build artifacts
#
# A Photos.app-like gallery that browses photos under a root folder WITHOUT
# importing anything: sidebar folder tree + thumbnail grid + full-size viewer.
# Open a folder with ⌘O, drop a folder on the window, or right-click a folder
# in Finder → Open With → MyGallery.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$DIR/build/mygallery"
SRC="$DIR/Sources/main.swift"
APP="$DIR/build/MyGallery.app"
INSTALL_DIR="/Applications/MyApplications"
INSTALLED="${INSTALL_DIR}/MyGallery.app"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
VERSION="$(tr -d ' \n' < "$DIR/VERSION" 2>/dev/null || echo 1.0)"

build() {
  mkdir -p "$DIR/build"
  echo "Building mygallery…"
  swiftc -O -framework AppKit -framework Vision -o "$BIN" "$SRC"
  echo "Built $BIN"
}

needs_build() {
  [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]
}

# Build the .icns from the master Resources/AppIcon.png if one exists.
build_icns() {
  local out="$1"
  local master="$DIR/Resources/AppIcon.png"
  if [ ! -f "$master" ]; then
    echo "no master Resources/AppIcon.png — skipping .icns" >&2
    return
  fi
  local tmp="$DIR/build/AppIcon.iconset"
  rm -rf "$tmp"; mkdir -p "$tmp"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$master" --out "$tmp/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$master" --out "$tmp/icon_${s}x${s}@2x.png" >/dev/null
  done
  if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns "$tmp" -o "$out" && echo "Built icon $out"
  else
    echo "iconutil not found — skipping .icns" >&2
  fi
  rm -rf "$tmp"
}

# Assemble a double-clickable .app bundle around the binary + Resources.
build_app() {
  needs_build && build
  echo "Packaging MyGallery.app…"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$BIN" "$APP/Contents/MacOS/mygallery"
  [ -d "$DIR/Resources" ] && cp -R "$DIR/Resources/." "$APP/Contents/Resources/" 2>/dev/null || true
  build_icns "$APP/Contents/Resources/AppIcon.icns"

  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>MyGallery</string>
  <key>CFBundleDisplayName</key>     <string>MyGallery</string>
  <key>CFBundleIdentifier</key>      <string>com.yosakata.mygallery</string>
  <key>CFBundleVersion</key>         <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleExecutable</key>      <string>mygallery</string>
  <key>CFBundleIconFile</key>        <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>  <string>11.0</string>
  <key>NSHighResolutionCapable</key> <true/>
  <key>NSPrincipalClass</key>        <string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>    <string>Folder</string>
      <key>CFBundleTypeRole</key>    <string>Viewer</string>
      <key>LSHandlerRank</key>       <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.folder</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "Built: $APP (v$VERSION)"
  echo
  echo "Double-click it in Finder, or run:  open \"$APP\""
}

case "${1:-install}" in
  build) build ;;
  app) build_app; open "$APP" ;;
  install)
    build_app
    echo "Installing to ${INSTALL_DIR}…"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    "$LSREG" -f "$INSTALLED" >/dev/null 2>&1 || true
    "$LSREG" -u "$APP" >/dev/null 2>&1 || true
    rm -rf "$APP"
    echo "Installed: $INSTALLED"
    echo
    echo "Launch from Spotlight (⌘Space → \"MyGallery\") or Launchpad."
    echo "Right-click a folder → Open With → MyGallery."
    ;;
  clean) rm -rf "$DIR/build"; echo "Cleaned." ;;
  -h|--help) grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *)
    echo "Unknown command: $1" >&2
    grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 1
    ;;
esac
