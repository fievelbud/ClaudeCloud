# Claude Desktop — Docker container with X11 GUI support
# Supports display via X11 forwarding or VNC (via x11vnc + Xvfb)
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CLAUDE_VERSION=latest

# ── System dependencies ────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Electron / GUI runtime
    libgtk-3-0 \
    libnotify4 \
    libnss3 \
    libxss1 \
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
    libxtst6 \
    # X11 / display
    xvfb \
    x11vnc \
    x11-utils \
    # Fonts
    fonts-liberation \
    fonts-noto-color-emoji \
    # Download tooling
    curl \
    wget \
    ca-certificates \
    gnupg \
    # Misc
    dbus-x11 \
    procps \
  && rm -rf /var/lib/apt/lists/*

# ── Download and install Claude Desktop (Linux .deb) ──────────────────────────
# Replace the URL below if Anthropic releases newer builds.
# Check https://claude.ai/download for the latest Linux package.
RUN if [ "$CLAUDE_VERSION" = "latest" ]; then \
      DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"; \
      echo "NOTE: No official Linux .deb is yet published by Anthropic."; \
      echo "      Provide CLAUDE_DEB_URL build-arg pointing to a .deb package, or"; \
      echo "      mount a pre-downloaded .deb via --build-arg CLAUDE_DEB_URL=<url>"; \
    fi

# Build-time override: pass a direct .deb URL with --build-arg CLAUDE_DEB_URL=...
ARG CLAUDE_DEB_URL=""
RUN if [ -n "$CLAUDE_DEB_URL" ]; then \
      wget -q "$CLAUDE_DEB_URL" -O /tmp/claude-desktop.deb && \
      apt-get update && \
      apt-get install -y --no-install-recommends /tmp/claude-desktop.deb && \
      rm /tmp/claude-desktop.deb && \
      rm -rf /var/lib/apt/lists/*; \
    fi

# ── Create a non-root user ────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash claude && \
    mkdir -p /home/claude/.config && \
    chown -R claude:claude /home/claude

# ── VNC password (default: "claude") — change via VNC_PASSWORD build-arg ──────
ARG VNC_PASSWORD=claude
RUN mkdir -p /home/claude/.vnc && \
    x11vnc -storepasswd "$VNC_PASSWORD" /home/claude/.vnc/passwd && \
    chown -R claude:claude /home/claude/.vnc

# ── Copy entrypoint ───────────────────────────────────────────────────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ── Expose VNC port ───────────────────────────────────────────────────────────
EXPOSE 5900

USER claude
WORKDIR /home/claude

# Default display resolution — override with DISPLAY_RESOLUTION env var
ENV DISPLAY=:99
ENV DISPLAY_RESOLUTION=1920x1080x24

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
