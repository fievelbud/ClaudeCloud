# syntax=docker/dockerfile:1
# ══════════════════════════════════════════════════════════════════════════════
# Stage 1 — builder
# Clones aaddrick/claude-desktop-debian and runs build.sh to produce a .deb
# ══════════════════════════════════════════════════════════════════════════════
FROM ubuntu:22.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive

# ── Build-tool dependencies ───────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    curl \
    ca-certificates \
    gnupg \
    sudo \
    # 7-zip — extracts the Windows .exe / .nupkg
    p7zip-full \
    # wrestool / icotool — extracts Windows icons
    icoutils \
    # ImageMagick — converts icons
    imagemagick \
    # .deb packaging
    dpkg-dev \
    fakeroot \
  && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 (the system nodejs on Ubuntu 22.04 is v12 — too old) ───────────
# Purge any Ubuntu-packaged nodejs/libnode-dev first to avoid dpkg conflicts
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get remove -y --purge nodejs libnode-dev npm 2>/dev/null || true && \
    apt-get autoremove -y && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── Non-root build user (build.sh refuses to run as root) ────────────────────
RUN useradd -m builduser && \
    echo 'builduser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# ── Clone the packaging repo ──────────────────────────────────────────────────
WORKDIR /build
RUN git clone --depth 1 --branch v1.3.23+claude1.1.7714 https://github.com/aaddrick/claude-desktop-debian.git . && \
    chown -R builduser:builduser /build

# ── Build the .deb  ───────────────────────────────────────────────────────────
# build.sh refuses to run as root — run as builduser with passwordless sudo
# Output: claude-desktop_<version>_amd64.deb (or arm64) in /build/
USER builduser
RUN DEBIAN_FRONTEND=noninteractive DPKG_DEB_COMPRESSOR_TYPE=xz bash build.sh --build deb
USER root

# Normalise to a fixed name so the runtime stage can COPY it without knowing
# the version string.
RUN mv /build/claude-desktop_*.deb /tmp/claude-desktop.deb

# ══════════════════════════════════════════════════════════════════════════════
# Stage 2 — runtime
# Clean Ubuntu image, installs the .deb + GUI stack, runs Claude Desktop
# ══════════════════════════════════════════════════════════════════════════════
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# ── Runtime system dependencies ───────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Electron / GUI runtime
    libgtk-3-0 \
    libnotify4 \
    libnss3 \
    libxss1 \
    libxshmfence1 \
    libxtst6 \
    xdg-utils \
    libatspi2.0-0 \
    libdrm2 \
    libgbm1 \
    libxcb-dri3-0 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    # Audio (required by Electron)
    libasound2 \
    # X11 / virtual display
    xvfb \
    x11-utils \
    # DBus (system tray, notifications)
    dbus-x11 \
    # Fonts
    fonts-liberation \
    fonts-noto-color-emoji \
    # Misc
    ca-certificates \
    gnupg \
    curl \
    wget \
    procps \
  && rm -rf /var/lib/apt/lists/*

# ── Xpra from xpra.org (includes full HTML5 client) ──────────────────────────
RUN wget -q -O /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc && \
    printf 'Types: deb\nURIs: https://xpra.org\nSuites: jammy\nComponents: main\nSigned-By: /usr/share/keyrings/xpra.asc\nArchitectures: amd64\n' \
        > /etc/apt/sources.list.d/xpra.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        xpra \
        xpra-x11 \
        xpra-html5 \
        python3-websockify \
    && rm -rf /var/lib/apt/lists/*

# ── Install the .deb built in Stage 1 ────────────────────────────────────────
COPY --from=builder /tmp/claude-desktop.deb /tmp/claude-desktop.deb
RUN apt-get update && \
    apt-get install -y --no-install-recommends /tmp/claude-desktop.deb && \
    rm /tmp/claude-desktop.deb && \
    rm -rf /var/lib/apt/lists/*

# ── Non-root user ─────────────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash claude && \
    mkdir -p /home/claude/.config /home/claude/.cache && \
    chown -R claude:claude /home/claude

# ── Entrypoint ────────────────────────────────────────────────────────────────
# Inline via BuildKit heredoc — no dependency on COPY from build context.
COPY <<'ENTRYPOINT_EOF' /usr/local/bin/entrypoint.sh
#!/usr/bin/env bash
# entrypoint.sh — starts Xpra with HTML5 browser client, then Claude Desktop
set -euo pipefail

# ── Privilege drop: fix volume permissions then re-exec as claude ─────────────
if [ "$(id -u)" = "0" ]; then
    mkdir -p /home/claude/.config/Claude/logs /home/claude/.cache/Claude
    chown -R claude:claude /home/claude/.config /home/claude/.cache
    exec su claude -s /bin/bash -c "exec /usr/local/bin/entrypoint.sh"
fi

DISPLAY_NUM="${DISPLAY#:}"
RESOLUTION="${DISPLAY_RESOLUTION:-1920x1080x24}"
DISPLAY_SIZE="${RESOLUTION%x*}"

# ── Find Claude Desktop binary ────────────────────────────────────────────────
# Resolve to the full path so xpra's child environment (stripped PATH) can find it.
CLAUDE_BIN=""
for candidate in /opt/Claude/claude-desktop /usr/bin/claude-desktop /usr/local/bin/claude-desktop; do
    if [ -x "$candidate" ]; then
        CLAUDE_BIN="$candidate"
        break
    fi
done

# Fall back: search common prefixes by name
if [ -z "$CLAUDE_BIN" ]; then
    for name in claude-desktop claude; do
        FOUND=$(command -v "$name" 2>/dev/null || true)
        if [ -n "$FOUND" ] && [ -x "$FOUND" ]; then
            CLAUDE_BIN="$FOUND"
            break
        fi
    done
fi

# Last resort: find any claude* executable under /opt or /usr
if [ -z "$CLAUDE_BIN" ]; then
    CLAUDE_BIN=$(find /opt /usr -type f -perm /u+x -name "claude*" 2>/dev/null \
        | grep -v '\.asar\|\.js\|\.css\|\.html\|\.png\|\.svg' \
        | head -1 || true)
fi

echo "[entrypoint] Installed claude* files:"
find /opt /usr -name "claude*" -type f 2>/dev/null | head -20 || true

if [ -z "$CLAUDE_BIN" ]; then
    echo "[entrypoint] ERROR: Claude Desktop binary not found."
    exit 1
fi
echo "[entrypoint] Using binary: ${CLAUDE_BIN}"
echo "[entrypoint] Script contents:"
cat "${CLAUDE_BIN}" || true
echo "[entrypoint] Electron binaries:"
find /usr/lib/claude-desktop /opt -type f -name "electron" 2>/dev/null || true

# ── Wrapper: call electron directly so output comes to us, not the launcher log ─
CLAUDE_LOG=/tmp/claude-output.log
CLAUDE_WRAPPER=/tmp/run-claude.sh
ELECTRON_BIN=/usr/lib/claude-desktop/node_modules/electron/dist/electron
ELECTRON_APP=/usr/lib/claude-desktop/node_modules/electron/dist/resources/app.asar
cat > "${CLAUDE_WRAPPER}" <<EOF
#!/bin/bash
export HOME=/home/claude
export XDG_CONFIG_HOME="\${HOME}/.config"
export XDG_CACHE_HOME="\${HOME}/.cache"
export XDG_DATA_HOME="\${HOME}/.local/share"
mkdir -p "\${HOME}/.config/Claude/logs" "\${HOME}/.cache/Claude"
LOG="${CLAUDE_LOG}"
echo "=== claude wrapper started at \$(date) ===" >> "\$LOG"
echo "DISPLAY: \${DISPLAY}" >> "\$LOG"
echo "--- electron output below ---" >> "\$LOG"
cd /usr/lib/claude-desktop
ELECTRON_ENABLE_LOGGING=1 "${ELECTRON_BIN}" \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-setuid-sandbox \
    "${ELECTRON_APP}" >> "\$LOG" 2>&1
echo "--- exit code: \$? ---" >> "\$LOG"
# Also print the launcher's own log if it exists
echo "--- launcher log ---" >> "\$LOG"
cat /home/claude/.config/Claude/logs/main.log >> "\$LOG" 2>/dev/null || true
EOF
chmod +x "${CLAUDE_WRAPPER}"


# ── Start Xpra (manages virtual display + serves HTML5 browser client) ────────
echo "[entrypoint] Starting Xpra on display :${DISPLAY_NUM} @ ${DISPLAY_SIZE}"
echo "[entrypoint] HTML5 client available on port 10000"
echo "[entrypoint] Launching ${CLAUDE_BIN}"

xpra start ":${DISPLAY_NUM}" \
    --bind-tcp=0.0.0.0:10000 \
    --html=on \
    --daemon=no \
    --start-child="${CLAUDE_WRAPPER}" \
    --exit-with-children=yes \
    --notifications=no \
    --bell=no \
    --mdns=no \
    --pulseaudio=no \
    --resize-display=yes \
    --sharing=yes || true

# ── Always print the claude-desktop log (even if empty) for diagnostics ───────
echo "[entrypoint] === claude-desktop log ==="
cat "${CLAUDE_LOG}" 2>/dev/null || echo "(no log file created)"
echo "[entrypoint] === end ==="
ENTRYPOINT_EOF
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 10000

WORKDIR /home/claude

ENV DISPLAY=:99
ENV DISPLAY_RESOLUTION=1920x1080x24

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
