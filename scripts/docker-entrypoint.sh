#!/usr/bin/env bash
# Entrypoint for the Cloud9 container. Binds 0.0.0.0 INSIDE the container (required for Docker's
# port-forward to reach it) but ONLY with HTTP basic auth enabled — c9 itself refuses to listen
# off-localhost without it. If you don't supply C9_USERNAME/C9_PASSWORD, a random password is
# generated and printed once to the logs.
set -euo pipefail

PORT="${PORT:-8181}"
USERNAME="${C9_USERNAME:-cloud9}"

if [ -z "${C9_PASSWORD:-}" ]; then
  PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)"
  echo "============================================================"
  echo "  Cloud9 generated a login (set C9_USERNAME/C9_PASSWORD to pin it):"
  echo "    username: ${USERNAME}"
  echo "    password: ${PASSWORD}"
  echo "============================================================"
else
  PASSWORD="${C9_PASSWORD}"
  echo "Cloud9 login: username '${USERNAME}' (password from C9_PASSWORD env)"
fi

exec node server.js \
  --port "${PORT}" \
  --listen 0.0.0.0 \
  -a "${USERNAME}:${PASSWORD}" \
  -w /workspace
