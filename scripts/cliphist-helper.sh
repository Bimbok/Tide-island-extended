#!/usr/bin/env bash
set -e

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tide-island/cliphist-imgs"
mkdir -p "$CACHE_DIR"

ACTION="${1:-list}"

case "$ACTION" in
    watch)
        command -v cliphist >/dev/null 2>&1 || exit 127
        command -v wl-paste >/dev/null 2>&1 || exit 127

        LOCK_FILE="${XDG_RUNTIME_DIR:-$CACHE_DIR}/tide-island-clipboard.lock"
        exec 9>"$LOCK_FILE"
        flock -n 9 || exit 0

        TEXT_PID=""
        IMAGE_PID=""

        cleanup() {
            [[ -n "$TEXT_PID" ]] && kill "$TEXT_PID" 2>/dev/null || true
            [[ -n "$IMAGE_PID" ]] && kill "$IMAGE_PID" 2>/dev/null || true
            exit 0
        }
        trap cleanup EXIT INT TERM HUP

        # Check and spawn text watcher if not already running
        if ! pgrep -f "wl-paste.*--type.*text.*cliphist" >/dev/null 2>&1; then
            wl-paste --type text --watch cliphist store &
            TEXT_PID=$!
        fi

        # Check and spawn image watcher if not already running
        if ! pgrep -f "wl-paste.*--type.*image.*cliphist" >/dev/null 2>&1; then
            wl-paste --type image --watch cliphist store &
            IMAGE_PID=$!
        fi

        # Keep running to supervise both background watchers
        if [[ -n "$TEXT_PID" || -n "$IMAGE_PID" ]]; then
            wait
        else
            while true; do
                sleep 3600 &
                wait $!
            done
        fi
        ;;
    list)
        if ! command -v cliphist >/dev/null 2>&1 || ! command -v wl-paste >/dev/null 2>&1 || ! command -v wl-copy >/dev/null 2>&1; then
            exit 127
        fi

        LIMIT="${2:-200}"
        DECODE_COUNT=0

        cliphist list 2>/dev/null | head -n "$LIMIT" | while IFS=$'\t' read -r id rest; do
            if [[ "$rest" == *"[[ binary data"* ]]; then
                img_path="$CACHE_DIR/$id.png"
                if [[ ! -s "$img_path" && $DECODE_COUNT -lt 8 ]]; then
                    tmp_path="$CACHE_DIR/$id.tmp.$$"
                    if cliphist decode "$id" > "$tmp_path" 2>/dev/null && [[ -s "$tmp_path" ]]; then
                        mv -f "$tmp_path" "$img_path"
                        DECODE_COUNT=$((DECODE_COUNT + 1))
                    else
                        rm -f "$tmp_path"
                    fi
                fi
                if [[ -s "$img_path" ]]; then
                    printf "%s\t%s\000icon\x1f%s\n" "$id" "$rest" "$img_path"
                else
                    printf "%s\t%s\000icon\x1f\n" "$id" "$rest"
                fi
            else
                printf "%s\t%s\n" "$id" "$rest"
            fi
        done
        ;;
    decode-missing)
        if ! command -v cliphist >/dev/null 2>&1; then
            exit 127
        fi

        LIMIT="${2:-200}"

        cliphist list 2>/dev/null | head -n "$LIMIT" | while IFS=$'\t' read -r id rest; do
            if [[ "$rest" == *"[[ binary data"* ]]; then
                img_path="$CACHE_DIR/$id.png"
                if [[ ! -s "$img_path" ]]; then
                    tmp_path="$CACHE_DIR/$id.tmp.$$"
                    if cliphist decode "$id" > "$tmp_path" 2>/dev/null && [[ -s "$tmp_path" ]]; then
                        mv -f "$tmp_path" "$img_path"
                        printf "%s\t%s\n" "$id" "$img_path"
                    else
                        rm -f "$tmp_path"
                    fi
                fi
            fi
        done
        ;;
    decode-img)
        id="$2"
        if [[ -n "$id" ]]; then
            img_path="$CACHE_DIR/$id.png"
            if [[ ! -s "$img_path" ]]; then
                tmp_path="$CACHE_DIR/$id.tmp.$$"
                if cliphist decode "$id" > "$tmp_path" 2>/dev/null && [[ -s "$tmp_path" ]]; then
                    mv -f "$tmp_path" "$img_path"
                else
                    rm -f "$tmp_path"
                fi
            fi
            if [[ -s "$img_path" ]]; then
                printf "%s\t%s\n" "$id" "$img_path"
            fi
        fi
        ;;
    copy)
        id="$2"
        if [[ -n "$id" ]]; then
            cliphist decode "$id" 2>/dev/null | wl-copy
        fi
        ;;
    delete)
        id="$2"
        delete_cache="${3:-true}"
        cache_img="$CACHE_DIR/$id.png"

        if [[ -n "$id" ]]; then
            cliphist list 2>/dev/null | grep -a "^${id}"$'\t' | cliphist delete 2>/dev/null || true
            if [[ "$delete_cache" == "true" && -f "$cache_img" ]]; then
                rm -f "$cache_img"
            fi
        fi
        ;;
    wipe|clear)
        cliphist wipe 2>/dev/null || true
        rm -rf "${CACHE_DIR:?}"/* 2>/dev/null || true
        ;;
    count)
        cliphist list 2>/dev/null | wc -l
        ;;
    *)
        if [[ -n "$1" ]]; then
            cliphist decode "$1" 2>/dev/null | wl-copy
        fi
        ;;
esac
