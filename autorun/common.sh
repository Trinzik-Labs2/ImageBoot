# Monotonic timestamps use shell builtins; missing clock affects logging only.
log() {
    CL_TIME=unknown
    if IFS=' ' read -r CL_NOW CL_REST < "${CUSTOMLOGO_CLOCK_FILE:-/proc/uptime}"; then CL_TIME=$CL_NOW; fi
    printf 'v3quick:t=%s:%s\n' "$CL_TIME" "$*"
    if [ -n "${CUSTOMLOGO_CARD_DIR:-}" ] && [ -d "$CUSTOMLOGO_CARD_DIR" ] &&
       [ ! -L "$CUSTOMLOGO_CARD_DIR/CustomLogo-status.txt" ]; then
        printf 'v3quick:t=%s:%s\n' "$CL_TIME" "$*" >> "$CUSTOMLOGO_CARD_DIR/CustomLogo-status.txt" 2>/dev/null || true
    fi
}
