#!/usr/bin/env bash
# install-ubuntu.sh — install the modernized Cloud9 IDE on Ubuntu/Debian WITHOUT Docker.
# Target: Ubuntu 22.04 / 24.04 (Debian works too). Run as a normal user that has sudo.
#
#   bash scripts/install-ubuntu.sh
#
# Env overrides: NODE_MAJOR=22  INSTALL_DIR=$HOME/c9  PORT=8181
set -euo pipefail

NODE_MAJOR="${NODE_MAJOR:-22}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/c9}"
PORT="${PORT:-8181}"

echo "==> [1/5] System dependencies (sudo)"
sudo apt-get update
sudo apt-get install -y curl git tmux build-essential python3 ca-certificates ripgrep

echo "==> [2/5] Node.js >= 20"
need_node=1
if command -v node >/dev/null 2>&1; then
  cur="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [ "$cur" -ge 20 ] && need_node=0 && echo "    found node $(node -v)"
fi
if [ "$need_node" -eq 1 ]; then
  echo "    installing Node.js ${NODE_MAJOR}.x via NodeSource"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
  sudo apt-get install -y nodejs
fi
echo "    node $(node -v) / npm $(npm -v)"

echo "==> [3/5] Source"
if [ -f "$(dirname "$0")/../server.js" ]; then
  SRC="$(cd "$(dirname "$0")/.." && pwd)"
  echo "    using existing checkout: $SRC"
else
  [ -d "$INSTALL_DIR/.git" ] || git clone https://github.com/c9/core.git "$INSTALL_DIR"
  SRC="$INSTALL_DIR"
  echo "    cloned into: $SRC"
fi
cd "$SRC"

echo "==> [4/5] npm deps + restore vendored modules (the c9 install dance)"
npm install --omit=dev --no-audit --no-fund
for i in $(git show HEAD:node_modules/ | tail -n +2); do
  [ -d "node_modules/$i" ] || git checkout HEAD -- "node_modules/$i"
done
rm -f package-lock.json

echo "==> [5/5] Modern-Node nodeBin fix (use the running node, not the stale ~/.c9 path)"
sed -i 's#\[path.join(installPath, win32 ? "node.exe" : "node/bin/node"), process.execPath\]#[process.execPath, path.join(installPath, win32 ? "node.exe" : "node/bin/node")]#' settings/standalone.js || true

mkdir -p "$HOME/workspace"
cat <<EOF

==> Done.  Start Cloud9:

    cd "$SRC"
    node server.js --port ${PORT} --listen 127.0.0.1 -w "\$HOME/workspace"

    then open http://localhost:${PORT}/ide.html

To run it as a background service, see the systemd unit in INSTALL.md.
SECURITY: keep --listen on 127.0.0.1 (or behind a reverse proxy with auth+TLS). This IDE gives
a terminal + filesystem access; do not expose it raw to the internet.
EOF
