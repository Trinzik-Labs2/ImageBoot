#!/bin/sh
# Existing firmware mpg123/ALSA; no mixer, routing or persistent setting writes.
set -eu
[ "$#" = 3 ] || exit 2
R=$1; SND=$2; PLAYER=$3
. "$R/common.sh"
[ -x "$PLAYER" ] || { log 'audio skipped: installed mpg123 unavailable'; exit 0; }
[ -r "$R/BootSound.mp3" ] || { log 'audio skipped: sound file unavailable'; exit 0; }
LINK=$(readlink "$SND/by-path/platform-sound") || { log 'audio skipped: platform sound card unavailable'; exit 0; }
NODE=${LINK##*/}
case "$NODE" in controlC*) CARD=${NODE#controlC};; *) log 'audio skipped: unexpected platform sound link'; exit 0;; esac
case "$CARD" in ''|*[!0-9]*) log 'audio skipped: malformed card number'; exit 0;; esac
[ "$CARD" -le 31 ] || { log 'audio skipped: card number out of bounds'; exit 0; }
[ -c "$SND/pcmC${CARD}D0p" ] || { log 'audio skipped: platform playback PCM unavailable'; exit 0; }
if "$R/speaker-route" --enable "$R/speaker.state" "$SND"; then
    log 'temporary speaker route checked/applied'
else
    log 'temporary speaker route unavailable; existing audio route retained'
fi
log "audio ready: ALSA hw:$CARD,0; waiting for first logo frame"
if ! IFS= read -r READY < "$R/sound-start"; then
    log 'audio skipped: first-frame signal unavailable'
    exit 0
fi
[ "$READY" = GO ] || { log 'audio skipped: invalid first-frame signal'; exit 0; }
log 'audio starting: BootSound.mp3 at half-scale (50%) gain'
exec "$PLAYER" -q --output alsa --audiodevice "hw:$CARD,0" --encoding s32 --rate 44100 --scale 16384 -- "$R/BootSound.mp3"
