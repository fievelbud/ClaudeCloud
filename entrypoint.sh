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

# ── Wrapper script so xpra captures claude-desktop stdout/stderr ──────────────
CLAUDE_LOG=/tmp/claude-output.log
CLAUDE_WRAPPER=/tmp/run-claude.sh
cat > "${CLAUDE_WRAPPER}" <<EOF
#!/bin/bash
exec "${CLAUDE_BIN}" --no-sandbox --disable-gpu --disable-dev-shm-usage "\$@" >> "${CLAUDE_LOG}" 2>&1
EOF
chmod +x "${CLAUDE_WRAPPER}"

# ── Chrome wrapper ────────────────────────────────────────────────────────────
CHROME_WRAPPER=/tmp/run-chrome.sh
cat > "${CHROME_WRAPPER}" <<EOF
#!/bin/bash
export HOME=/home/claude
export XDG_CONFIG_HOME="\${HOME}/.config"
export XDG_CACHE_HOME="\${HOME}/.cache"
mkdir -p "\${HOME}/.config/google-chrome"
exec google-chrome-stable \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-setuid-sandbox \
    --user-data-dir="\${HOME}/.config/google-chrome"
EOF
chmod +x "${CHROME_WRAPPER}"

# ── Ensure /tmp/.X11-unix exists with correct permissions ─────────────────────
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

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
    --start-child="${CHROME_WRAPPER}" \
    --exit-with-children=yes \
    --notifications=no \
    --bell=no \
    --mdns=no \
    --pulseaudio=no \
    --resize-display=yes \
    --sharing=yes || true

# ── Print claude-desktop output to surface crash details in docker logs ───────
if [ -f "${CLAUDE_LOG}" ] && [ -s "${CLAUDE_LOG}" ]; then
    echo "[entrypoint] === claude-desktop output ==="
    cat "${CLAUDE_LOG}"
    echo "[entrypoint] === end ==="
fi
