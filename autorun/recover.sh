#!/bin/sh
set -eu
R=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec >> "$R/runtime.log" 2>&1
. "$R/common.sh"
    if [ -e "$R/speaker.state" ]; then
        if "$R/speaker-route" --restore "$R/speaker.state" /dev/snd; then
            log 'speaker/microphone snapshot restored'
        else
            log 'speaker route restore failed; stock restart still requested'
        fi
    fi
# Preserve command stderr in a separate card file without affecting recovery.
if [ -n "${CUSTOMLOGO_CARD_DIR:-}" ] && [ -d "$CUSTOMLOGO_CARD_DIR" ] &&
   [ ! -L "$CUSTOMLOGO_CARD_DIR/CustomLogo-runtime.txt" ]; then
    cat "$R/runtime.log" > "$CUSTOMLOGO_CARD_DIR/CustomLogo-runtime.txt" 2>/dev/null || true
fi
[ -e "$R/restore-needed" ] || { log 'finished without stopping stock'; exit 0; }
# Do not block on our own After=ac50 ordering. The manager may reject this
# request during shutdown. A queued start is not proof of healthy stock UI.
if systemctl --no-block start ac50.service; then
    log 'stock restart request accepted'
else
    log 'stock restart request FAILED (or shutdown in progress)'
    exit 1
fi
