#!/bin/sh
# Batched integrity/copy operations, same no-prompt supervised architecture.
set -eu
D=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
note() {
    CL_TIME=unknown
    if IFS=' ' read -r CL_NOW CL_REST < "${CUSTOMLOGO_CLOCK_FILE:-/proc/uptime}"; then CL_TIME=$CL_NOW; fi
    if [ ! -L "$D/CustomLogo-status.txt" ]; then
        printf 'v3quick:dispatcher:t=%s:%s\n' "$CL_TIME" "$*" >> "$D/CustomLogo-status.txt" 2>/dev/null || true
    fi
}
note entered
[ "$(id -u)" = 0 ] || { note 'skip: not root'; exit 0; }
grep -q ' /run tmpfs ' /proc/mounts || { note 'skip: /run is not tmpfs'; exit 0; }
command -v systemd-run >/dev/null 2>&1 || { note 'skip: missing systemd-run'; exit 0; }
note 'source verification started'
[ "$(sha256sum "$D/runtime.sha256" | cut -d' ' -f1)" = '9f8fc5f02f1445e8e10019f9ec3f4b6109f079e32c757c1bb63f8850e5e9579e' ] || { note 'checksum failed: source manifest'; exit 0; }
if CHECK_OUTPUT=$(cd "$D" && sha256sum -c runtime.sha256 2>&1); then :; else
    note 'source checksum check failed'; note "$CHECK_OUTPUT"; exit 0
fi
note 'source verification complete'
R=/run/customlogo-v2
umask 077
mkdir "$R" 2>/dev/null || { note 'skip: already attempted or runtime unavailable'; exit 0; }
note 'RAM staging started'
cp "$D/worker.sh" "$D/common.sh" "$D/recover.sh" "$D/play-sound.sh" "$D/splash-drm" "$D/animate-drm" "$D/speaker-route" "$D/media-prepare" "$D/runtime.sha256" "$R/" || { note 'RAM staging failed'; exit 0; }
[ "$(sha256sum "$R/runtime.sha256" | cut -d' ' -f1)" = '9f8fc5f02f1445e8e10019f9ec3f4b6109f079e32c757c1bb63f8850e5e9579e' ] || { note 'checksum failed: RAM manifest'; exit 0; }
if CHECK_OUTPUT=$(cd "$R" && sha256sum -c runtime.sha256 2>&1); then :; else
    note 'RAM checksum check failed'; note "$CHECK_OUTPUT"; exit 0
fi
chmod 700 "$R/splash-drm" "$R/animate-drm" "$R/speaker-route" "$R/media-prepare"
note 'RAM staging and verification complete'
if systemd-run --unit=customlogo-v2 --collect --no-block \
    --setenv="CUSTOMLOGO_CARD_DIR=$D" \
    --property=After=ac50.service \
    --property=RuntimeMaxSec=65 --property=TimeoutStartSec=5 \
    --property=TimeoutStopSec=8 --property=KillMode=control-group \
    --property=Restart=no \
    --property="ExecStopPost=/bin/sh $R/recover.sh" \
    /bin/sh "$R/worker.sh" "$R" '/usr/bin/MPC Sample' /proc /usr/bin/az0x-splashctl "$R/splash-drm" \
    > "$R/dispatch.log" 2>&1; then
    note 'worker request accepted'
else
    note 'worker request FAILED'
    if [ ! -L "$D/CustomLogo-status.txt" ]; then cat "$R/dispatch.log" >> "$D/CustomLogo-status.txt" 2>/dev/null || true; fi
fi
