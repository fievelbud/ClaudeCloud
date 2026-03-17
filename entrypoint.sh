#!/usr/bin/env bash
# entrypoint.sh — starts Xpra with HTML5 browser client, then Claude Desktop
set -euo pipefail

DISPLAY_NUM="${DISPLAY#:}"                     # strip leading colon  → e.g. "99"
RESOLUTION="${DISPLAY_RESOLUTION:-1920x1080x24}"
DISPLAY_SIZE="${RESOLUTION%x*}"                # "1920x1080x24" → "1920x1080"

# ── Find Claude Desktop binary ────────────────────────────────────────────────
# aaddrick/claude-desktop-debian installs to /opt/Claude/claude-desktop
# Fall back to PATH-based lookup for other package formats
CLAUDE_BIN=""
for candidate in /opt/Claude/claude-desktop claude-desktop claude; do
    if [ -x "$candidate" ] || command -v "$candidate" > /dev/null 2>&1; then
        CLAUDE_BIN="$candidate"
        break
    fi
done

if [ -z "$CLAUDE_BIN" ]; then
    echo "[entrypoint] ERROR: Claude Desktop binary not found."
    echo "             The .deb built from aaddrick/claude-desktop-debian"
    echo "             should install to /opt/Claude/claude-desktop."
    exit 1
fi

# ── Start Xpra (manages virtual display + serves HTML5 browser client) ────────
echo "[entrypoint] Starting Xpra on display :${DISPLAY_NUM} @ ${DISPLAY_SIZE}"
echo "[entrypoint] HTML5 client available on port 10000"
echo "[entrypoint] Launching ${CLAUDE_BIN}"

exec xpra start ":${DISPLAY_NUM}" \
    --bind-tcp=0.0.0.0:10000 \
    --html=on \
    --daemon=no \
    --start-child="${CLAUDE_BIN} --no-sandbox --disable-gpu" \
    --exit-with-children=yes \
    --notifications=no \
    --bell=no \
    --mdns=no \
    --pulseaudio=no \
    --resize-display=yes \
    --sharing=yes
