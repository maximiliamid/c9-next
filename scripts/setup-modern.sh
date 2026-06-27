#!/bin/bash
# setup-modern.sh — reproducible install of c9-core on a modern Node (verified on Node 24.4.0 / npm 11).
#
# Why this exists: `npm install` on npm >=3 DELETES the vendored modules that c9 commits
# into node_modules (amd-loader, architect, c9, smith, treehugger, ...) because they are
# not declared in package.json. The upstream install-sdk.sh restores them via
# `git checkout HEAD -- node_modules`. This script does the minimum needed to get a
# clean, runnable tree without the global ~/.c9 install dance.
set -e
cd "$(dirname "$0")/.."

echo "==> node: $(node --version)   npm: $(npm --version)"

echo "==> npm install --production (omit dev)"
npm install --omit=dev --no-audit --no-fund

echo "==> restoring vendored node_modules deleted by npm"
for i in $(git show HEAD:node_modules/ | tail -n +2); do
  [ -d "node_modules/$i" ] || (git checkout HEAD -- "node_modules/$i" && echo "    restored: $i")
done

# npm writes a lockfile that does not reflect the vendored modules; drop it to match upstream.
rm -f package-lock.json

echo "==> done. Start with: scripts/start-modern.sh"
