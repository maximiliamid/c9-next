# Installing Cloud9 (modernized) on Ubuntu / Linux

The full Cloud9 IDE — file tree, multi-pane editor (Ace), tabs, terminal, run/debug, preview —
made to run on a current Node.js. Two ways to install: **Docker** (recommended, also fixes the
terminal) or **bare-metal**.

> ⚠️ **Security.** This IDE is remote-code-execution *by design*: it gives anyone who can reach
> it a terminal and filesystem access on the host/container. Keep it on `127.0.0.1` or behind a
> reverse proxy with **auth + TLS**. Never publish the raw port to the internet.

---

## Option A — Docker + TLS (recommended)

One command. The Linux container ships `tmux` + build tools (terminal works out of the box),
and `docker compose` puts a **Caddy HTTPS reverse proxy** in front so c9 is never exposed on the
plaintext surface (c9 is RCE-by-design — keep it behind TLS + auth).

```bash
cp .env.example .env        # then set a STRONG C9_PASSWORD (and pick C9_HTTPS_PORT)
docker compose up -d --build
# → open https://<host>:8443/ide.html   (login with C9_USERNAME / C9_PASSWORD)
```

- Only Caddy's HTTPS port (default **8443**) is published; **c9 itself is internal-only**.
- TLS uses Caddy's **self-signed** CA by default (no domain / no port 80 needed) → the browser
  warns "not trusted"; click through. Traffic is still encrypted.
- **Real trusted cert later:** point a domain at the host, free port 80, and replace the `:8443`
  block in `Caddyfile` with `your.domain { reverse_proxy c9:8181 }` — Caddy auto-issues Let's Encrypt.
- Manage: `docker compose logs -f` · `docker compose down` · `docker compose up -d --build` (update).

### Plain HTTP (localhost dev only — no TLS)

```bash
docker build -t c9 .
docker run -d --name c9 -p 127.0.0.1:8181:8181 \
  -e C9_USERNAME=cloud9 -e C9_PASSWORD=yourpass \
  -v "$PWD/workspace:/workspace" c9
# → http://localhost:8181/ide.html   (bound to localhost only)
```

### Exposing it to a team (do this, not a raw public port)
Put a TLS-terminating reverse proxy with auth in front (Caddy example):

```
ide.example.com {
    basic_auth { youruser <bcrypt-hash> }   # minimum; prefer real SSO
    reverse_proxy 127.0.0.1:8181
}
```

Keep the container bound to `127.0.0.1:8181` on the host so only the proxy can reach it.

---

## Option B — Bare metal (no Docker)

```bash
bash scripts/install-ubuntu.sh
```

Installs Node 22 (NodeSource), `git`, `tmux`, `build-essential`, `python3`, `ripgrep`, then does
the npm install + vendored-module restore + the modern-Node `nodeBin` fix. When it finishes:

```bash
node server.js --port 8181 --listen 127.0.0.1 -w "$HOME/workspace"
# → http://localhost:8181/ide.html
```

### Run it as a service (systemd)

`/etc/systemd/system/c9.service`:

```ini
[Unit]
Description=Cloud9 IDE
After=network.target

[Service]
Type=simple
User=YOUR_USER
WorkingDirectory=/home/YOUR_USER/c9
ExecStart=/usr/bin/node server.js --port 8181 --listen 127.0.0.1 -w /home/YOUR_USER/workspace
Restart=on-failure
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now c9
sudo systemctl status c9
```

---

## Requirements

| | Docker route | Bare-metal route |
|---|---|---|
| OS | any with Docker | Ubuntu 22.04 / 24.04 (Debian ok) |
| Node | bundled in image (24) | installed by the script (>=20) |
| Terminal | works (tmux in image) | needs `tmux` (script installs it) |
| Persistence | `./workspace` volume | `~/workspace` dir |

## Known limitations (this is the legacy core)

- Dependencies are EOL (see `MODERNIZE.md`) — fine for trusted single-user/team use, **not** for
  raw public exposure.
- Some skins may log a LESS warning; cosmetic.
- For the long-term modern rewrite (multi-tenant hosting, modern stack) see `../c9-next`.
