#!/bin/bash
#
# sync-backups.sh
#
# ExFAT HDD 間の同期スクリプト。
# ソースを正として、ターゲットをソースに合わせる（ターゲット側の余分なファイルは削除）。
# 日本語ファイル名（NFD/NFC）に対応。
#
# 使い方:
#   sync-backups.sh <source> <target>
#   sync-backups.sh -n <source> <target>          # dry-run（確認のみ、変更なし）
#   sync-backups.sh -y <source> <target>          # 確認プロンプトをスキップ
#   sync-backups.sh --report [FILE] <source> <target>  # 差分サマリをファイルに書き出し
#
# 例:
#   sync-backups.sh /Volumes/backup1 /Volumes/backup2
#   sync-backups.sh --report ~/Desktop/diff.txt /Volumes/backup1 /Volumes/backup2
#

set -euo pipefail

# ---------------------------------------------------------------------------
# 設定
# ---------------------------------------------------------------------------

DRY_RUN=0
ASSUME_YES=0
REPORT_MODE=0
REPORT_FILE="${HOME}/Desktop/sync_backups_report_$(date '+%Y%m%d_%H%M%S').txt"
LOG_FILE="${HOME}/Library/Logs/sync-backups.log"

# Homebrew rsync を優先（--iconv で NFD/NFC 正規化に対応）
if [[ -x /opt/homebrew/bin/rsync ]]; then
    RSYNC=/opt/homebrew/bin/rsync
elif [[ -x /usr/local/bin/rsync ]]; then
    RSYNC=/usr/local/bin/rsync
else
    RSYNC=rsync
fi

# ExFAT はパーミッション・拡張属性を持たないので除外
# --modify-window=2: ExFAT のタイムスタンプ誤差を許容
# --iconv=UTF-8-MAC,UTF-8: macOS(NFD) <-> ExFAT(NFC) のファイル名正規化
RSYNC_OPTS=(-rlt --delete --modify-window=2)
if "$RSYNC" --help 2>&1 | grep -q iconv; then
    RSYNC_OPTS+=(--iconv=UTF-8-MAC,UTF-8)
fi

# macOS が自動生成するメタデータファイル・フォルダを除外
RSYNC_OPTS+=(
    --exclude='.DS_Store'
    --exclude='._*'
    --exclude='.Spotlight-V100/'
    --exclude='.Trashes/'
    --exclude='.TemporaryItems/'
    --exclude='.fseventsd/'
)

# ---------------------------------------------------------------------------
# ヘルパー関数
# ---------------------------------------------------------------------------

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
    exit 1
}

# ---------------------------------------------------------------------------
# 引数パース
# ---------------------------------------------------------------------------

ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1; shift ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --report)
            REPORT_MODE=1
            # 次の引数が HDD パス（/Volumes/...）でなければファイルパスとして使う
            if [[ $# -gt 1 && "$2" != -* && "$2" != /Volumes/* ]]; then
                REPORT_FILE="$2"; shift
            fi
            shift ;;
        -h|--help)    usage ;;
        -*)           die "不明なオプション: $1" ;;
        *)            ARGS+=("$1"); shift ;;
    esac
done

[[ ${#ARGS[@]} -eq 2 ]] || usage

SOURCE="${ARGS[0]%/}/"
TARGET="${ARGS[1]%/}/"

# ---------------------------------------------------------------------------
# バリデーション
# ---------------------------------------------------------------------------

mkdir -p "$(dirname "$LOG_FILE")"

[[ -d "$SOURCE" ]] || die "ソースが見つかりません: $SOURCE"
[[ -d "$TARGET" ]] || die "ターゲットが見つかりません: $TARGET"

SOURCE_REAL=$(cd "$SOURCE" && pwd -P)
TARGET_REAL=$(cd "$TARGET" && pwd -P)
[[ "$SOURCE_REAL" != "$TARGET_REAL" ]] || die "ソースとターゲットが同じパスです: $SOURCE_REAL"

# ソースが空の場合は中止（HDD マウント忘れ対策）
[[ -n "$(ls -A "$SOURCE")" ]] || die "ソースが空です（マウントされていない可能性があります）: $SOURCE"

# ---------------------------------------------------------------------------
# 開始
# ---------------------------------------------------------------------------

log "=== sync-backups.sh 開始 ==="
log "source : $SOURCE_REAL"
log "target : $TARGET_REAL"
log "rsync  : $("$RSYNC" --version | head -1)"
if [[ $REPORT_MODE -eq 1 ]]; then
    log "モード  : レポート出力 → $REPORT_FILE"
elif [[ $DRY_RUN -eq 1 ]]; then
    log "モード  : dry-run（変更なし）"
else
    log "モード  : 本番実行"
fi

# ---------------------------------------------------------------------------
# Step 1: dry-run で差分確認
# ---------------------------------------------------------------------------

log "差分を確認中..."
DIFF_FILE=$(mktemp -t hdd_sync.XXXXXX)
trap 'rm -f "$DIFF_FILE"' EXIT

"$RSYNC" "${RSYNC_OPTS[@]}" --dry-run --itemize-changes \
    "$SOURCE" "$TARGET" > "$DIFF_FILE" 2>&1 || true

ADD_COUNT=$(grep -c '^>f+++++++++' "$DIFF_FILE" || true)
ALL_MOD=$(grep  -c '^>f'          "$DIFF_FILE" || true)
DEL_COUNT=$(grep -c '^\*deleting' "$DIFF_FILE" || true)
UPD_COUNT=$(( ALL_MOD - ADD_COUNT ))

log "差分: 追加=$ADD_COUNT 更新=$UPD_COUNT 削除=$DEL_COUNT"

if [[ $((ADD_COUNT + UPD_COUNT + DEL_COUNT)) -eq 0 && $REPORT_MODE -eq 0 ]]; then
    log "すでに同期済み。終了します。"
    exit 0
fi

# 削除対象の最初の10件を表示
if [[ $DEL_COUNT -gt 0 ]]; then
    log "削除対象（最初の10件）:"
    grep '^\*deleting' "$DIFF_FILE" | head -10 | sed 's/^/  /' | tee -a "$LOG_FILE" || true
fi

# ---------------------------------------------------------------------------
# Step 2: レポートモード
# ---------------------------------------------------------------------------

if [[ $REPORT_MODE -eq 1 ]]; then
    # 差分があるフォルダ一覧を抽出
    FOLDERS=$(grep -E '^(>f|\*deleting)' "$DIFF_FILE" \
        | sed 's|^[^ ]* *||' \
        | sed 's|/[^/]*$||' \
        | sort -u || true)

    {
        echo "sync-backups 差分レポート"
        echo "生成日時 : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "source   : $SOURCE_REAL"
        echo "target   : $TARGET_REAL"
        echo "差分     : 追加=$ADD_COUNT 更新=$UPD_COUNT 削除=$DEL_COUNT"
        echo ""

        echo "=== 差分があるフォルダ ==="
        if [[ -n "$FOLDERS" ]]; then
            while IFS= read -r dir; do
                add=$(grep -c "^>f+++++++++ *${dir}/" "$DIFF_FILE" || true)
                all=$(grep -c "^>f[^ ]* *${dir}/" "$DIFF_FILE" || true)
                del=$(grep -c "^\*deleting *${dir}/" "$DIFF_FILE" || true)
                upd=$(( all - add ))
                echo "  $dir  (追加=$add 更新=$upd 削除=$del)"
            done <<< "$FOLDERS"
        else
            echo "  （なし）"
        fi

        echo ""
        echo "=== ソースにしかないファイル（ターゲットに追加される） ==="
        grep '^>f+++++++++' "$DIFF_FILE" | sed 's/^[^ ]* */  /' || true

        echo ""
        echo "=== ターゲットにしかないファイル（削除される） ==="
        grep '^\*deleting' "$DIFF_FILE" | sed 's/^\*deleting */  /' || true

    } > "$REPORT_FILE"

    log "レポートを書き出しました: $REPORT_FILE"
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 3: dry-run モードなら終了
# ---------------------------------------------------------------------------

if [[ $DRY_RUN -eq 1 ]]; then
    log "dry-run 完了。変更はありません。"
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 4: 確認プロンプト
# ---------------------------------------------------------------------------

if [[ $ASSUME_YES -ne 1 ]]; then
    echo
    echo "  ソース    : $SOURCE_REAL"
    echo "  ターゲット: $TARGET_REAL"
    echo "  追加=$ADD_COUNT 更新=$UPD_COUNT 削除=$DEL_COUNT"
    echo
    read -r -p "同期を実行しますか？ [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || die "中止しました。"
fi

# ---------------------------------------------------------------------------
# Step 5: 同期実行
# ---------------------------------------------------------------------------

log "同期開始..."
caffeinate -i "$RSYNC" "${RSYNC_OPTS[@]}" --progress "$SOURCE" "$TARGET"
log "=== 完了 ==="
