#!/usr/bin/env bash
# build.sh — build the MyMarkdown GUI app (native Swift macOS markdown
# viewer + plain-text editor).
#
# Usage:
#   ./build.sh install   build + copy to /Applications/MyApplications (launch from Spotlight/Launchpad)
#   ./build.sh app       build a double-clickable MyMarkdown.app in build/
#   ./build.sh build     compile the raw binary only
#   ./build.sh clean     remove build artifacts
#
# Once installed, launch from Spotlight/Launchpad and drag a file onto the window
# (or press ⌘O). Markdown files (.md etc.) open as a live-reloading preview;
# any other file opens in the built-in text editor (the former "mini editor").
#
# Self-contained: compiles every Swift file under Sources/ (main.swift +
# AppShared.swift) into one binary. No external build library.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_NAME="mymarkdown"
APP_DISPLAY_NAME="MyMarkdown"
BUNDLE_ID="com.yosakata.mymarkdown"
INSTALL_NOTES='Right-click a file → Open With → MyMarkdown (markdown renders; other files open in the editor).'
PLIST_EXTRA='  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>    <string>Markdown Document</string>
      <key>CFBundleTypeRole</key>    <string>Viewer</string>
      <key>LSHandlerRank</key>       <string>Alternate</string>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>md</string>
        <string>markdown</string>
        <string>mdown</string>
        <string>mkd</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key>    <string>Text Document</string>
      <key>CFBundleTypeRole</key>    <string>Editor</string>
      <key>LSHandlerRank</key>       <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.plain-text</string>
        <string>public.text</string>
        <string>public.source-code</string>
        <string>public.data</string>
      </array>
    </dict>
  </array>'

BIN="$DIR/build/$BIN_NAME"
SRCS=("$DIR"/Sources/*.swift)
APP="$DIR/build/$APP_DISPLAY_NAME.app"
INSTALL_DIR="/Applications/MyApplications"
INSTALLED="${INSTALL_DIR}/$APP_DISPLAY_NAME.app"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# App version, single source of truth (bumped each commit).
VERSION="$(tr -d ' \n' < "$DIR/VERSION" 2>/dev/null || echo 1.0)"

build() {
  mkdir -p "$DIR/build"
  echo "Building ${BIN_NAME}…"
  swiftc -O -framework AppKit -framework WebKit -o "$BIN" "${SRCS[@]}"
  echo "Built $BIN"
}

# Rebuild if the binary is missing or any Swift source is newer than it.
needs_build() {
  [ ! -x "$BIN" ] && return 0
  local f
  for f in "${SRCS[@]}"; do [ "$f" -nt "$BIN" ] && return 0; done
  return 1
}

# Build the .icns from the master Resources/AppIcon.png (needs sips + iconutil).
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
  echo "Packaging ${APP_DISPLAY_NAME}.app…"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"
  # Copy the *contents* of Resources/ directly into Contents/Resources/ so that
  # resourcesDirectory()'s "exeDir/../Resources" candidate (= Contents/Resources)
  # finds template.html — not a nested Resources/Resources.
  cp -R "$DIR/Resources/." "$APP/Contents/Resources/"
  build_icns "$APP/Contents/Resources/AppIcon.icns"

  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleDisplayName</key>     <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key>         <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleExecutable</key>      <string>${BIN_NAME}</string>
  <key>CFBundleIconFile</key>        <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>  <string>11.0</string>
  <key>NSHighResolutionCapable</key> <true/>
${PLIST_EXTRA:-}
</dict>
</plist>
PLIST

  # Ad-hoc codesign so Gatekeeper/launchd are happy with the local bundle.
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "Built: $APP (v$VERSION)"
  echo
  echo "Double-click it in Finder, or run:  open \"$APP\""
}

do_install() {
  build_app
  echo "Installing to ${INSTALL_DIR}…"
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALLED"
  cp -R "$APP" "$INSTALLED"
  # Register with Launch Services so it shows up in Spotlight / "Open With".
  "$LSREG" -f "$INSTALLED" >/dev/null 2>&1 || true
  # Remove the build/ bundle so it isn't ALSO indexed by Launch Services,
  # which would show a duplicate icon in Launchpad / "Open With".
  "$LSREG" -u "$APP" >/dev/null 2>&1 || true
  rm -rf "$APP"
  echo "Installed: $INSTALLED"
  echo
  echo "Launch it from Spotlight (⌘Space → \"$APP_DISPLAY_NAME\") or Launchpad."
  if [ -n "${INSTALL_NOTES:-}" ]; then echo "$INSTALL_NOTES"; fi
}

app_build_main() {
  case "${1:-install}" in
    build)   build ;;
    app)     build_app; open "$APP" ;;
    install) do_install ;;
    clean)   rm -rf "$DIR/build"; echo "Cleaned." ;;
    -h|--help)
      grep '^#' "$DIR/build.sh" | sed 's/^# \{0,1\}//'
      ;;
    *)
      echo "Unknown command: $1" >&2
      grep '^#' "$DIR/build.sh" | sed 's/^# \{0,1\}//' >&2
      exit 1
      ;;
  esac
}

app_build_main "$@"
