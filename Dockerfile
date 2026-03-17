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
    # 7-zip — extracts the Windows .exe / .nupkg
    p7zip-full \
    # wrestool / icotool — extracts Windows icons
    icoutils \
    # ImageMagick — converts icons
    imagemagick \
    # .deb packaging
    dpkg-dev \
    fakeroot \
    # Node.js runtime (build.sh will auto-download v20 if system version is low,
    # but providing it here avoids the extra download and speeds up the build)
    nodejs \
    npm \
  && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 (the system nodejs on Ubuntu 22.04 is v12 — too old) ───────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── Clone the packaging repo ──────────────────────────────────────────────────
WORKDIR /build
RUN git clone --depth 1 https://github.com/aaddrick/claude-desktop-debian.git .

# ── Build the .deb  ───────────────────────────────────────────────────────────
# Runs as root inside Docker — build.sh detects this and skips sudo.
# Output: claude-desktop_<version>_amd64.deb (or arm64) in /build/
RUN DEBIAN_FRONTEND=noninteractive DPKG_DEB_COMPRESSOR_TYPE=xz bash build.sh --build deb

# Normalise to a fixed name so the runtime stage can COPY it without knowing
# the version string.
RUN mv claude-desktop_*.deb /tmp/claude-desktop.deb

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
    # X11 / virtual display / Xpra
    xvfb \
    x11-utils \
    xpra \
    python3-websockify \
    # DBus (system tray, notifications)
    dbus-x11 \
    # Fonts
    fonts-liberation \
    fonts-noto-color-emoji \
    # Misc
    ca-certificates \
    procps \
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
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 10000

USER claude
WORKDIR /home/claude

ENV DISPLAY=:99
ENV DISPLAY_RESOLUTION=1920x1080x24

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
