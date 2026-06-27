# Modernized Cloud9 IDE (full IDE) — installable on any Linux via Docker.
#
#   docker build -t c9 .
#   docker run -d --name c9 -p 8181:8181 -v "$PWD/workspace:/workspace" c9
#   open http://localhost:8181/ide.html
#
# The Linux container also fixes the terminal that's painful on macOS: tmux + build tools are
# present so node-pty / the pty path work.
FROM node:24-bookworm-slim

# Build/runtime essentials: git (vendored restore + git deps), tmux (terminal backend),
# python3/make/g++ (node-pty native build), ripgrep (fast search).
# Plus a general dev + netsec toolset so the in-IDE terminal is actually usable
# (python/php/nmap/curl/... ). Add more here as you need them — it's just apt.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git tmux make g++ ca-certificates ripgrep \
      python3 python3-pip python-is-python3 php-cli \
      curl wget vim nano less jq unzip zip tree htop procps \
      net-tools dnsutils iputils-ping nmap sudo openssh-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/c9
COPY . /opt/c9

# Install registry deps fresh for Linux, then restore the vendored modules that npm>=3 deletes
# (amd-loader, architect, c9, smith, treehugger, ...) from git — the classic c9 install dance,
# captured reproducibly here instead of the global ~/.c9 installer.
RUN git config --global --add safe.directory /opt/c9 \
 && npm install --omit=dev --no-audit --no-fund \
 && for i in $(git show HEAD:node_modules/ | tail -n +2); do \
        [ -d "node_modules/$i" ] || git checkout HEAD -- "node_modules/$i"; \
    done \
 && rm -f package-lock.json

# Workspace mount point. Bind a host dir here to persist your files.
RUN mkdir -p /workspace && chmod +x scripts/docker-entrypoint.sh
ENV PORT=8181
EXPOSE 8181

# Any HTTP response (200, or 401 when basic auth is on) means the server is up.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:8181/ide.html',()=>process.exit(0)).on('error',()=>process.exit(1))"

# The entrypoint binds 0.0.0.0 inside the container WITH basic auth (c9 refuses off-localhost
# without it). Supply C9_USERNAME / C9_PASSWORD, or read the generated password from the logs.
# SECURITY: this IDE is remote-code-execution by design. Even with basic auth, put TLS in front
# and prefer keeping the host port on 127.0.0.1. Do NOT publish raw to the internet.
ENTRYPOINT ["bash", "scripts/docker-entrypoint.sh"]
