#!/usr/bin/env bash
#
# kindle-transfer.sh
# ------------------
# Amazon Kindle Fire (Fire OS / Android) の SD カード・内部ストレージの中身を
# USB 経由で macOS にコピーする対話型ツール。
#
# 仕組み: Android Debug Bridge (adb) の `adb pull` を使う。
#   - macOS がうまく扱えない MTP ではなく adb を使うので安定して動く
#   - SD カードを自動検出（/storage/XXXX-XXXX 形式のボリューム）
#   - 内部ストレージ (/sdcard) もコピー可能
#
# 事前準備（Kindle 側で一度だけ）:
#   1. 設定 → デバイスオプション → シリアル番号を7回タップ → 開発者オプション出現
#   2. 設定 → デバイスオプション → 開発者オプション → 「ADB を有効にする / USB デバッグ」をオン
#   3. データ通信対応の USB ケーブルで Mac に接続
#   4. Kindle 画面に出る「USB デバッグを許可しますか？」で「許可」をタップ
#
# 使い方:
#   chmod +x kindle-transfer.sh
#   ./kindle-transfer.sh
#
set -uo pipefail

# ---- 表示ヘルパー -----------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YEL=$'\033[33m'; BLU=$'\033[34m'; CYA=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; CYA=""; RST=""
fi

info()  { printf '%s\n' "${CYA}ℹ️  $*${RST}"; }
ok()    { printf '%s\n' "${GRN}✅ $*${RST}"; }
warn()  { printf '%s\n' "${YEL}⚠️  $*${RST}"; }
err()   { printf '%s\n' "${RED}❌ $*${RST}" >&2; }
title() { printf '\n%s\n' "${BOLD}${BLU}$*${RST}"; }

abort() { err "$*"; exit 1; }

# ---- adb の確認 / インストール ---------------------------------------------
ensure_adb() {
  if command -v adb >/dev/null 2>&1; then
    return
  fi

  warn "adb (Android Platform Tools) が見つかりません。"
  if command -v brew >/dev/null 2>&1; then
    printf '%s' "${BOLD}Homebrew でインストールしますか？ [Y/n]: ${RST}"
    read -r reply
    case "${reply:-Y}" in
      [Nn]*) abort "adb が必要です。'brew install --cask android-platform-tools' を実行してから再度お試しください。" ;;
      *)
        info "インストール中: brew install --cask android-platform-tools"
        brew install --cask android-platform-tools || abort "adb のインストールに失敗しました。"
        ;;
    esac
  else
    abort "Homebrew が見つかりません。https://brew.sh からインストール後、'brew install --cask android-platform-tools' を実行してください。"
  fi

  command -v adb >/dev/null 2>&1 || abort "インストール後も adb が見つかりません。"
  ok "adb の準備ができました。"
}

# ---- デバイス接続待ち -------------------------------------------------------
# 接続済みかつ authorized なデバイスのシリアルを SERIAL に入れる
SERIAL=""
wait_for_device() {
  title "Kindle Fire の接続を確認しています…"
  info "Kindle を USB で接続し、画面の「USB デバッグを許可」をタップしてください。"

  while true; do
    # adb サーバを起動（初回は時間がかかることがある）
    adb start-server >/dev/null 2>&1

    # device 一覧（ヘッダ行と空行を除去）
    local lines
    lines="$(adb devices | sed '1d' | sed '/^[[:space:]]*$/d' | tr -d '\r')"

    local authorized=""
    local unauthorized=""
    while IFS=$'\t ' read -r dev state _; do
      [[ -z "$dev" ]] && continue
      case "$state" in
        device)       authorized+="$dev"$'\n' ;;
        unauthorized) unauthorized+="$dev"$'\n' ;;
      esac
    done <<< "$lines"

    authorized="$(printf '%s' "$authorized" | sed '/^$/d')"
    unauthorized="$(printf '%s' "$unauthorized" | sed '/^$/d')"

    if [[ -n "$authorized" ]]; then
      local count
      count="$(printf '%s\n' "$authorized" | wc -l | tr -d ' ')"
      if [[ "$count" -eq 1 ]]; then
        SERIAL="$authorized"
        ok "デバイスを検出しました: ${SERIAL}"
        return
      fi
      # 複数台 → 選択
      title "複数のデバイスが見つかりました。コピー元を選んでください:"
      local i=1
      local -a serials=()
      while IFS= read -r s; do
        local model
        model="$(adb -s "$s" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
        printf '  %s) %s  %s\n' "$i" "$s" "${DIM}${model}${RST}"
        serials+=("$s"); ((i++))
      done <<< "$authorized"
      printf '%s' "${BOLD}番号: ${RST}"; read -r pick
      if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#serials[@]} )); then
        SERIAL="${serials[$((pick-1))]}"
        ok "選択: ${SERIAL}"
        return
      fi
      warn "入力が無効です。もう一度。"
      continue
    fi

    if [[ -n "$unauthorized" ]]; then
      warn "デバイスは見えていますが未承認です。Kindle 画面の「USB デバッグを許可」をタップしてください。"
    fi

    printf '%s' "${DIM}待機中… 接続できたら自動で進みます (Ctrl+C で中止)${RST}\r"
    sleep 2
  done
}

ADB() { adb -s "$SERIAL" "$@"; }

# ---- ストレージ検出 ---------------------------------------------------------
# SD カード (/storage/XXXX-XXXX) と内部ストレージを探す
SD_PATH=""
SD_LABEL=""
detect_storage() {
  title "ストレージを検出しています…"
  local listing
  listing="$(ADB shell ls -1 /storage 2>/dev/null | tr -d '\r')"

  # XXXX-XXXX 形式（SD カードの典型的なボリューム ID）を探す
  SD_PATH=""
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ "$name" =~ ^[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}$ ]]; then
      SD_PATH="/storage/$name"
      SD_LABEL="$name"
      break
    fi
  done <<< "$listing"

  if [[ -n "$SD_PATH" ]]; then
    ok "SD カードを検出: ${SD_PATH}"
  else
    warn "SD カードらしきボリュームが見つかりませんでした（未挿入か未マウントの可能性）。"
  fi
}

# ---- コピー元の選択 ---------------------------------------------------------
SRC=""
choose_source() {
  title "コピー元を選んでください:"
  local -a paths=() labels=()
  if [[ -n "$SD_PATH" ]]; then
    paths+=("$SD_PATH"); labels+=("SD カード  (${SD_PATH})")
  fi
  paths+=("/sdcard"); labels+=("内部ストレージ全体  (/sdcard)")
  paths+=("/sdcard/DCIM"); labels+=("写真・動画のみ  (/sdcard/DCIM)")
  paths+=("__custom__"); labels+=("パスを手入力する")

  local i=1
  for l in "${labels[@]}"; do
    printf '  %s) %s\n' "$i" "$l"; ((i++))
  done
  local default=1
  printf '%s' "${BOLD}番号 [既定: ${default}]: ${RST}"; read -r pick
  pick="${pick:-$default}"
  if ! [[ "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > ${#paths[@]} )); then
    abort "入力が無効です。"
  fi
  local chosen="${paths[$((pick-1))]}"
  if [[ "$chosen" == "__custom__" ]]; then
    printf '%s' "${BOLD}コピー元のパス (例: /sdcard/Download): ${RST}"; read -r chosen
    [[ -z "$chosen" ]] && abort "パスが空です。"
  fi
  SRC="$chosen"

  # 存在確認
  if ! ADB shell "[ -e '$SRC' ]" 2>/dev/null; then
    abort "指定のパスが Kindle 上に見つかりません: $SRC"
  fi
  ok "コピー元: ${SRC}"
}

# ---- コピー先の選択 ---------------------------------------------------------
DEST=""
choose_dest() {
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local default="$HOME/Downloads/Kindle-$stamp"
  title "コピー先（Mac 側）を入力してください:"
  printf '%s' "${BOLD}保存先 [既定: ${default}]: ${RST}"; read -r d
  DEST="${d:-$default}"
  # ~ 展開
  DEST="${DEST/#\~/$HOME}"
  mkdir -p "$DEST" || abort "コピー先を作成できません: $DEST"
  ok "コピー先: ${DEST}"
}

# ---- 転送 -------------------------------------------------------------------
do_pull() {
  title "転送を開始します"
  info "元 : ${SRC}  (Kindle)"
  info "先 : ${DEST}  (Mac)"
  printf '%s' "${BOLD}この内容でコピーしますか？ [Y/n]: ${RST}"; read -r go
  case "${go:-Y}" in [Nn]*) abort "中止しました。" ;; esac

  echo
  info "コピー中… (大きいデータは時間がかかります)"
  # SRC の「中身」を DEST 直下に入れるため末尾に /. を付ける
  local start; start="$(date +%s)"
  if ADB pull -a "$SRC/." "$DEST"; then
    local end; end="$(date +%s)"
    echo
    ok "転送が完了しました！ ($((end-start))秒)"
    info "保存先: ${DEST}"
    # サイズ表示
    local size; size="$(du -sh "$DEST" 2>/dev/null | cut -f1)"
    [[ -n "$size" ]] && info "コピーされた容量: ${size}"
    # Finder で開く
    printf '%s' "${BOLD}Finder で開きますか？ [Y/n]: ${RST}"; read -r open_it
    case "${open_it:-Y}" in [Nn]*) : ;; *) open "$DEST" ;; esac
  else
    err "転送中にエラーが発生しました。USB 接続とケーブル（データ通信対応か）をご確認ください。"
    exit 1
  fi
}

# ---- メイン -----------------------------------------------------------------
main() {
  printf '%s\n' "${BOLD}${BLU}📱➡️💻  Kindle Fire → Mac ファイル転送ツール${RST}"
  printf '%s\n' "${DIM}adb (Android Debug Bridge) 経由で SD カード等をコピーします${RST}"
  ensure_adb
  wait_for_device
  detect_storage
  choose_source
  choose_dest
  do_pull
}

main "$@"
