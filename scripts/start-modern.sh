#!/bin/bash
# start-modern.sh — launch c9-core for local single-user development on a modern Node.
#
# SECURITY: binds to 127.0.0.1 ONLY. The standalone build is remote-code-execution by
# design (terminal + filesystem rooted at your home dir) and its auth is a stub. Do NOT
# expose this port to a LAN or the internet, and never pass `-a :` (forces no-login),
# until the hardening in MODERNIZE.md (real auth, TLS, Origin pinning, sandboxing) is done.
set -e
cd "$(dirname "$0")/.."

PORT="${PORT:-8181}"
WORKSPACE="${1:-$(pwd)}"

echo "==> Cloud9 (modern-Node fork) on http://127.0.0.1:${PORT}/ide.html"
echo "==> workspace: ${WORKSPACE}"
echo "==> bound to 127.0.0.1 only (do not expose; see MODERNIZE.md)"

# nodeBin is fixed to process.execPath in settings/standalone.js so the VFS child fork
# and file-search (filelist.js) both use the running Node instead of the stale ~/.c9 path.
exec node server.js \
  --port "${PORT}" \
  --listen 127.0.0.1 \
  -w "${WORKSPACE}"
