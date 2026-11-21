#!/bin/sh
# Fixed internal interface, invoked by our independent systemd unit only.
set -eu
[ "$#" = 5 ] || exit 2
R=$1; APP=$2; PROC=$3; HELPER=$4; DRM=$5
SETTLE_SECONDS=0
DISPLAY_SECONDS=3
exec >> "$R/runtime.log" 2>&1
. "$R/common.sh"
log 'worker started'
log "timing: settle=$SETTLE_SECONDS display=$DISPLAY_SECONDS"
log 'full firmware hash started'
ACTUAL=
if [ -x /usr/bin/openssl ]; then
    if HASH_LINE=$(/usr/bin/openssl dgst -sha256 -r "$APP"); then
        ACTUAL=${HASH_LINE%% *}
        case "$ACTUAL" in ''|*[!0-9a-f]*) ACTUAL=;; esac
        [ "${#ACTUAL}" = 64 ] || ACTUAL=
        [ -z "$ACTUAL" ] || log 'firmware hash backend: openssl'
    fi
fi
if [ -z "$ACTUAL" ]; then
    log 'firmware hash backend: sha256sum fallback'
    ACTUAL=$(sha256sum "$APP" | cut -d' ' -f1) || { log 'skip: stock hash unreadable'; exit 0; }
fi
if [ "$ACTUAL" != 'b6584cba76e416e432ad202509099d34373dc2c3d6a8fb625f5678bf0193b508' ]; then
    log "skip: full firmware hash mismatch: $ACTUAL"
    exit 0
fi
log 'full firmware hash matched'
log 'drop-in media preparation started'
if [ -z "${CUSTOMLOGO_CARD_DIR:-}" ] || ! "$R/media-prepare" --prepare "$CUSTOMLOGO_CARD_DIR/image" "$CUSTOMLOGO_CARD_DIR/sound" "$R"; then
    log 'skip: invalid drop-in media; stock remains running'
    exit 0
fi
log 'drop-in media ready in RAM'

ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40; do
    PID=$(systemctl show ac50.service -p MainPID --value) || { log 'skip: MainPID query failed'; exit 0; }
    case "$PID" in ''|*[!0-9]*) log 'skip: malformed MainPID'; exit 0;; esac
    if [ "$PID" -gt 1 ] && [ "$(readlink "$PROC/$PID/exe" 2>/dev/null || true)" = "$APP" ]; then
        ready=1; break
    fi
    sleep 1
done
[ "$ready" = 1 ] || { log 'skip: stock app never became ready'; exit 0; }
# Wider than v1's arbitrary 45-second gate; late insertion still refused.
awk '{exit !($1 >= 0 && $1 < 120)}' "$PROC/uptime" || { log 'skip: late card invocation'; exit 0; }
if [ "$SETTLE_SECONDS" -gt 0 ]; then
    log "stock ready; settling for $SETTLE_SECONDS seconds"
    sleep "$SETTLE_SECONDS"
else
    log 'stock ready; no fixed settling delay'
fi
: > "$R/restore-needed"
log 'requesting stock stop'
if ! systemctl stop ac50.service; then
    log 'stock stop failed; recovery requested by supervisor'
    exit 1
fi
# Confirm shutdown succeeded before opening any display interface.
if systemctl is-active --quiet ac50.service; then
    log 'stock remains active; refusing display ownership'
    exit 1
fi
log 'stock stopped'
# Release daemon ownership once; no stock image command is used for animation.
if [ -x "$HELPER" ]; then
    log 'releasing stock splash display before native animation'
    if ! "$HELPER" drop-display; then
        log 'native animation refused: splash release failed'
        exit 1
    fi
fi
log 'starting native single-session fade'
AUDIO_PID=
cleanup_audio() {
    if [ -n "$AUDIO_PID" ]; then
        # Only our own unreaped child PID; ensure PCM closes before stock restart.
        kill -TERM "$AUDIO_PID" 2>/dev/null || true
        kill -KILL "$AUDIO_PID" 2>/dev/null || true
        if wait "$AUDIO_PID"; then
            log 'audio process finished'
        else
            log 'audio process ended or stopped at logo completion'
        fi
        AUDIO_PID=
    fi
    if [ -e "$R/speaker.state" ]; then
        if "$R/speaker-route" --restore "$R/speaker.state" /dev/snd; then
            log 'speaker/microphone snapshot restored'
        else
            log 'speaker route restore failed; stock restart still requested'
        fi
    fi
    rm -f "$R/sound-start"
}
trap cleanup_audio EXIT
trap 'exit 1' INT TERM
if [ -f "$R/BootSound.mp3" ] && mkfifo "$R/sound-start"; then
    /bin/sh "$R/play-sound.sh" "$R" /dev/snd /usr/bin/mpg123 &
    AUDIO_PID=$!
else
    log 'audio skipped: no MP3 or RAM first-frame FIFO unavailable'
fi
run_native_fade() {
    if [ -n "$AUDIO_PID" ]; then
        "$R/animate-drm" --animate-notify "$R/eyes.frames" /dev/dri/card0 "$R/sound-start"
    else
        "$R/animate-drm" --animate "$R/eyes.frames" /dev/dri/card0
    fi
}
if run_native_fade; then
    log 'native fade completed; supervisor will restore stock'
    exit 0
fi
cleanup_audio
log 'native fade failed; trying static fallback'
shown=0
if [ -x "$HELPER" ]; then
    log 'trying stock PNG utility'
    if "$HELPER" show-image --drop "$R/splash.png"; then
        log 'stock PNG utility returned success'
        shown=1
        sleep "$DISPLAY_SECONDS"
    else
        log 'stock PNG utility failed; trying original DRM renderer'
    fi
else
    log 'stock PNG utility unavailable; trying original DRM renderer'
fi
if [ "$shown" = 0 ]; then
    if "$DRM" --display "$R/frame.bgrx" /dev/dri/card0 "$DISPLAY_SECONDS"; then
        log 'original DRM renderer completed'
    else
        log 'original DRM renderer failed'
        exit 1
    fi
fi
log 'display phase complete; supervisor will restore stock'
