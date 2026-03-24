#!/usr/bin/env bash
# entrypoint.sh — starts Xpra with HTML5 browser client, then Claude Desktop
set -euo pipefail

DISPLAY_NUM="${DISPLAY#:}"                     # strip leading colon  → e.g. "99"
RESOLUTION="${DISPLAY_RESOLUTION:-1920x1080x24}"
DISPLAY_SIZE="${RESOLUTION%x*}"                # "1920x1080x24" → "1920x1080"

# ── Find Claude Desktop binary ────────────────────────────────────────────────
CLAUDE_BIN=""
for candidate in /opt/Claude/claude-desktop claude-desktop claude; do
    if [ -x "$candidate" ] || command -v "$candidate" > /dev/null 2>&1; then
        CLAUDE_BIN="$candidate"
        break
    fi
done

if [ -z "$CLAUDE_BIN" ]; then
    echo "[entrypoint] ERROR: Claude Desktop binary not found."
    exit 1
fi

echo "[entrypoint] Installed claude* files:"
find /usr /opt -name 'claude*' 2>/dev/null | sort
echo "[entrypoint] Using binary: ${CLAUDE_BIN}"
echo "[entrypoint] Script contents:"
cat "${CLAUDE_BIN}"
echo "[entrypoint] Electron binaries:"
find /usr /opt -name 'electron' -type f 2>/dev/null

# ── Clear stale VM bundle so Claude Desktop downloads a fresh matching one ────
VM_BUNDLE_DIR="/home/claude/.config/Claude/vm_bundles"
if [ -d "${VM_BUNDLE_DIR}" ]; then
    echo "[entrypoint] Clearing stale VM bundle from ${VM_BUNDLE_DIR}"
    rm -rf "${VM_BUNDLE_DIR}"
fi

# ── Wrapper that restarts Claude Desktop automatically on crash ───────────────
CLAUDE_LOG=/tmp/claude-output.log
CLAUDE_WRAPPER=/tmp/run-claude.sh
cat > "${CLAUDE_WRAPPER}" <<WRAPPER_EOF
#!/bin/bash
CLAUDE_BIN="${CLAUDE_BIN}"
CLAUDE_LOG="${CLAUDE_LOG}"
while true; do
    "\${CLAUDE_BIN}" --no-sandbox --disable-gpu --disable-dev-shm-usage "\$@" >> "\${CLAUDE_LOG}" 2>&1
    echo "[claude-wrapper] Claude Desktop exited (\$?), restarting in 5s..." >> "\${CLAUDE_LOG}"
    sleep 5
done
WRAPPER_EOF
chmod +x "${CLAUDE_WRAPPER}"

# ── Clean up stale X11/Xpra lock files from previous container runs ───────────
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
rm -f "/tmp/xpra/${DISPLAY_NUM}/server.pid"

# ── Start Xpra (manages virtual display + serves HTML5 browser client) ────────
echo "[entrypoint] Starting Xpra on display :${DISPLAY_NUM} @ ${DISPLAY_SIZE}"
echo "[entrypoint] HTML5 client available on port 10000"
echo "[entrypoint] Launching ${CLAUDE_BIN}"

xpra start ":${DISPLAY_NUM}" \
    --bind-tcp=0.0.0.0:10000 \
    --html=on \
    --daemon=no \
    --start-child="${CLAUDE_WRAPPER}" \
    --exit-with-children=no \
    --notifications=no \
    --bell=no \
    --mdns=no \
    --pulseaudio=no \
    --resize-display=yes \
    --sharing=yes
