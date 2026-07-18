#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./build_app.sh

APP_NAME=PassMan
echo "==> /Applications へコピー"
cp -R "${APP_NAME}.app" "/Applications/${APP_NAME}.app"
echo "==> 完了: /Applications/${APP_NAME}.app"
open "/Applications/${APP_NAME}.app"
