#!/usr/bin/env bash
# entrypoint.sh — starts Xvfb virtual display, optional VNC, then Claude Desktop
set -euo pipefail

DISPLAY_NUM="${DISPLAY#:}"          # strip leading colon  → e.g. "99"
RESOLUTION="${DISPLAY_RESOLUTION:-1920x1080x24}"

# ── 1. Start Xvfb (virtual framebuffer) ───────────────────────────────────────
echo "[entrypoint] Starting Xvfb on :${DISPLAY_NUM} @ ${RESOLUTION}"
Xvfb ":${DISPLAY_NUM}" -screen 0 "${RESOLUTION}" -ac +extension GLX +render -noreset &
XVFB_PID=$!

# Wait for the display to be ready
for i in $(seq 1 20); do
    DISPLAY=":${DISPLAY_NUM}" xdpyinfo > /dev/null 2>&1 && break
    sleep 0.5
done

# ── 2. Start VNC server (optional — skip by setting NO_VNC=1) ─────────────────
if [ "${NO_VNC:-0}" != "1" ]; then
    echo "[entrypoint] Starting x11vnc on port 5900"
    x11vnc \
        -display ":${DISPLAY_NUM}" \
        -rfbport 5900 \
        -rfbauth /home/claude/.vnc/passwd \
        -forever \
        -shared \
        -noxdamage \
        -quiet &
    VNC_PID=$!
    echo "[entrypoint] VNC ready — connect to port 5900 (password in VNC_PASSWORD)"
fi

# ── 3. Launch Claude Desktop ──────────────────────────────────────────────────
# Find the installed binary (package may name it claude or claude-desktop)
CLAUDE_BIN=""
# aaddrick/claude-desktop-debian installs to /opt/Claude/claude-desktop
# Fall back to PATH-based lookup for other package formats
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
    echo ""
    echo "[entrypoint] Keeping container alive for debugging (VNC/X11 is up)."
    wait $XVFB_PID
    exit 1
fi

echo "[entrypoint] Launching ${CLAUDE_BIN}"
DISPLAY=":${DISPLAY_NUM}" exec "$CLAUDE_BIN" \
    --no-sandbox \
    --disable-gpu \
    "$@"
