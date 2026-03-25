# CLAUDE.md — ClaudeCloud Repository Guide

This file provides guidance for AI assistants (Claude Code and others) working in this repository.

## Repository Overview

**Project:** ClaudeCloud (`fievelbud/ClaudeCloud`)
**Status:** Newly initialized repository — no source code exists yet.

This CLAUDE.md was auto-generated on 2026-03-17 to establish conventions before development begins. Update each section as the project grows.

---

## Git Workflow

### Branch Naming

All AI-assisted work branches must follow this pattern:

```
claude/<short-description>-<session-id>
```

Example: `claude/add-claude-documentation-6XrlS`

- **Never push directly to `main`** without explicit user approval.
- Always use `git push -u origin <branch-name>`.
- If a push fails with HTTP 403, verify the branch name starts with `claude/` and ends with the correct session ID.

### Commit Messages

Write clear, imperative commit messages:

```
Add initial project scaffold
Fix authentication token refresh logic
Update CLAUDE.md with API conventions
```

- One sentence summary (≤72 chars) as the first line.
- Leave a blank line before any extended description.
- Do not include "AI-generated" disclaimers in commit messages unless the project convention requires it.

### Push Retry Policy

If `git push` fails due to a network error (not HTTP 403), retry with exponential backoff:

| Attempt | Wait before retry |
|---------|------------------|
| 1       | 2 seconds        |
| 2       | 4 seconds        |
| 3       | 8 seconds        |
| 4       | 16 seconds       |

After 4 failed attempts, report the error to the user.

---

## Development Conventions

> **Update this section** as the stack and conventions are decided.

### General Rules

- Keep changes minimal and focused — fix what was asked, nothing more.
- Prefer editing existing files over creating new ones.
- Do not add docstrings, comments, or type annotations to code you did not change.
- Do not add error handling for scenarios that cannot happen.
- Avoid backwards-compatibility shims for unused code.

### Security

- Never commit secrets, API keys, tokens, or credentials.
- Do not introduce command injection, XSS, SQL injection, or other OWASP Top 10 vulnerabilities.
- Validate input only at system boundaries (user input, external APIs); trust internal code.

---

## File Structure

```
ClaudeCloud/
├── CLAUDE.md              # This file — AI assistant guide
├── Dockerfile             # Builds the Claude Desktop container image
├── docker-compose.yml     # Orchestrates the container with volumes & ports
└── entrypoint.sh          # Container startup: Xvfb → VNC → Claude Desktop
```

Update this tree as directories and files are added to the project.

---

## Docker — Claude Desktop

### How it works

The image uses a **multi-stage build**:

1. **Builder stage** — clones [`fievelbud/claude-desktop-debian`](https://github.com/fievelbud/claude-desktop-debian)
   (fork of aaddrick) pinned to commit **`a1a7d55`** = aaddrick tag `v1.3.23+claude1.1.7714`
   (pinned — do not upgrade without testing COWORK_VM),
   downloads the official Claude Desktop Windows installer, extracts the
   Electron app, patches it for Linux, and packages it as a `.deb`.
2. **Runtime stage** — installs the `.deb` into a clean Ubuntu 22.04 image,
   adds a virtual display (Xvfb) and VNC server (x11vnc).

```
build.sh (aaddrick) → .deb → Ubuntu 22.04 + Xvfb :99 → x11vnc :5900 → VNC client
```

No pre-built `.deb` URL is needed — everything is built automatically during
`docker compose build`.

### Prerequisites

- Docker ≥ 24 and Docker Compose v2
- Internet access at build time (to clone the repo and download the installer)

### Build

```bash
docker compose build
```

The build takes a few minutes the first time. Subsequent builds are faster due
to Docker layer caching.

To change the VNC password at build time:

```bash
VNC_PASSWORD=mysecret docker compose build
```

### Run

```bash
docker compose up -d
```

Then connect a VNC client to `localhost:5900`.
Default password: **`claude`** (set `VNC_PASSWORD` env var to change it).

### X11 forwarding (Linux hosts only)

For native-speed rendering without VNC, comment out the `ports` block in
`docker-compose.yml`, uncomment the X11 blocks, then run:

```bash
xhost +local:docker
docker compose up -d
```

### Environment variables

| Variable            | Default        | Description                          |
|---------------------|----------------|--------------------------------------|
| `VNC_PASSWORD`      | `claude`       | VNC login password (build-time arg)  |
| `VNC_PORT`          | `5900`         | Host port mapped to container VNC    |
| `DISPLAY_RESOLUTION`| `1920x1080x24` | Virtual display resolution & depth   |
| `NO_VNC`            | `0`            | Set to `1` to skip the VNC server    |

### Persistent data

Two named volumes keep your config and cache across container restarts:

| Volume         | Container path               |
|----------------|------------------------------|
| `claude_config`| `/home/claude/.config/Claude`|
| `claude_cache` | `/home/claude/.cache/Claude` |

To reset all data: `docker compose down -v`

---

## Tasks for AI Assistants

When asked to implement something:

1. Read the relevant files before modifying them.
2. Make the smallest change that satisfies the requirement.
3. Run any tests or linters that exist in the project.
4. Commit with a clear message.
5. Push to the designated `claude/` branch.

When asked a question about the codebase:

1. Search the codebase with Grep/Glob before answering.
2. Cite specific file paths and line numbers in your response.
3. Do not guess — if the code doesn't exist yet, say so.

---

## Updating This File

Whenever the project structure, tooling, or conventions change significantly, update the relevant sections of this file. Keep it accurate and concise — it is read on every AI session.
