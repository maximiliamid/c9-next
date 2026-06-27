#!/usr/bin/env bash
# verify-docker.sh — regression gate for core modernization. Rebuilds the image, runs it with
# basic auth, and asserts the IDE still serves. Used after every dependency/Node-compat change.
#   bash scripts/verify-docker.sh
set -uo pipefail
cd "$(dirname "$0")/.."

NAME=c9-verify
PORT="${PORT:-8182}"
USER=verify
PASS=verify123

echo "==> build"
docker build -t c9:verify . >/tmp/c9-verify-build.log 2>&1 || { echo "BUILD FAILED:"; tail -25 /tmp/c9-verify-build.log; exit 1; }

docker rm -f "$NAME" >/dev/null 2>&1 || true
echo "==> run"
docker run -d --name "$NAME" -e C9_USERNAME=$USER -e C9_PASSWORD=$PASS \
  -p 127.0.0.1:$PORT:8181 -v /tmp/c9-verify-ws:/workspace c9:verify >/dev/null || { echo "RUN FAILED"; exit 1; }

echo "==> probe"
noauth=$(curl -s -o /dev/null -w "%{http_code}" --retry 20 --retry-delay 1 --retry-all-errors "http://127.0.0.1:$PORT/ide.html")
auth=$(curl -s -u $USER:$PASS -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/ide.html")
title=$(curl -s -u $USER:$PASS "http://127.0.0.1:$PORT/ide.html" | grep -oE '<title>[^<]*</title>' | head -1)
errs=$(docker logs "$NAME" 2>&1 | grep -iE "error|throw|cannot find|valid node" | grep -viE "error_handler|errorHandler" | head -5)

docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "----------------------------------------"
echo "no-auth (expect 401): $noauth"
echo "auth    (expect 200): $auth"
echo "title             : ${title:-<none>}"
echo "log errors        : ${errs:-<none>}"
echo "----------------------------------------"
[ "$auth" = "200" ] && [ "$noauth" = "401" ] && echo "PASS ✅" || { echo "FAIL ❌"; exit 1; }
