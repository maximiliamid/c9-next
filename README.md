# Cloud9 — Modernized

A browser-based IDE — code editor, file tree, integrated terminal, and run/debug — that runs as
a single self-hosted service. This is a **continued-development fork** of the discontinued
Cloud9 v3 core, brought up to date to run on **current Node.js (22–24)** and **modern Linux**,
shipped as a **Docker image** you can stand up in one command.

> Status: **working** — boots and serves the full IDE on Node 24, with the editor and terminal
> verified end-to-end. See [`MODERNIZATION-LOG.md`](./MODERNIZATION-LOG.md) for what's been
> modernized and what's next.

---

## Quick start (Docker + TLS) — recommended

One command, with an HTTPS reverse proxy in front:

```bash
cp .env.example .env          # set a strong C9_PASSWORD, and C9_HOST (your IP/domain)
docker compose up -d --build
# → open https://<C9_HOST>:8443/ide.html   (login with C9_USERNAME / C9_PASSWORD)
```

- Only the HTTPS port (default **8443**) is published; the IDE itself stays internal.
- TLS uses a self-signed cert by default (no domain needed) — the browser warns once, click through.
- IP-only host? Set `C9_HOST=<your-ip>.nip.io` (free wildcard DNS) so the cert matches.
- Real trusted cert: point a domain at the host + free port 80 → Caddy auto-issues Let's Encrypt.

### Plain HTTP (localhost dev only)

```bash
docker build -t cloud9 .
docker run -d --name cloud9 -p 127.0.0.1:8181:8181 \
  -e C9_USERNAME=dev -e C9_PASSWORD=yourpass \
  -v "$PWD/workspace:/workspace" cloud9
# → http://localhost:8181/ide.html
```

### Bare metal (Ubuntu/Debian, no Docker)

```bash
bash scripts/install-ubuntu.sh
node server.js --port 8181 --listen 127.0.0.1 -w "$HOME/workspace"
```

Full instructions (systemd service, reverse proxy, requirements): [`INSTALL.md`](./INSTALL.md).

---

## What's inside

- **Editor** — Ace, with syntax highlighting, themes, multi-pane tabs.
- **Terminal** — real shell via `node-pty` + `tmux` (baked into the image).
- **Filesystem** — file tree, open/save, search (ripgrep), watch.
- **Run / preview** — run code and preview output from the browser.
- **Plugin architecture** — the IDE is composed of plugins via a dependency-injection runtime.

## Configuration

The server reads `--port`, `--listen`, `-w <workspace>`, `--auth user:pass`, `--secure <cert>`,
`--collab`, and more — run `node server.js --help` for the full list. In Docker, set
`C9_USERNAME` / `C9_PASSWORD` / `C9_HOST` / `C9_HTTPS_PORT` / `C9_WORKSPACE` via `.env`.

## ⚠️ Security

This IDE gives whoever can log in a **terminal and filesystem access** on the host/container —
treat it as remote code execution by design. Always run it **behind authentication and TLS**
(the Docker setup does both), keep it off the public plaintext surface, and prefer isolating each
deployment (container/VM, non-root, scoped workspace). Don't expose it raw to the internet.

## Project layout

```
server.js            entry point
configs/             server + client plugin graphs (architect)
plugins/             the IDE plugins (editor, terminal, fs, run, ...)
scripts/             setup-modern.sh, start-modern.sh, install-ubuntu.sh, verify-docker.sh
Dockerfile           modern Node 24 image (tmux + node-pty + ripgrep)
docker-compose.yml   c9 (internal) + Caddy TLS reverse proxy
```

## Development

```bash
scripts/setup-modern.sh     # install deps + restore vendored modules (once)
scripts/start-modern.sh     # run on 127.0.0.1:8181
scripts/verify-docker.sh    # build the image and assert the IDE serves
```

## License

Apache License 2.0 — see [`LICENSE`](./LICENSE) and [`NOTICE`](./NOTICE). This project is a fork
of the open-source Cloud9 v3 core and retains that license.
