# Cloud9 core — modernization notes (continued-development fork)

Upstream `c9/core` is discontinued. This document records the state of running it on a
modern Node and the realistic paths forward. Assessed on **Node v24.4.0 / npm 11.4.2**,
macOS (darwin 25.2.0).

## TL;DR — it already runs on Node 24

The discontinued core **boots unmodified on Node 24** and serves the IDE:

```
Connect server listening at http://127.0.0.1:8181
Cloud9 is up and running
GET /ide.html -> HTTP 200   (real Cloud9 page, ~30 KB)
```

"Get it booting on a modern Node" was ~80% done out of the box. The hard-removed-API
landmines (`path.exists`, `crypto.createCipher`) sit on code paths the **standalone**
config never loads, so they don't block boot.

## What was changed in this fork (Stage 0)

1. **`settings/standalone.js`** — `nodeBin` now lists `process.execPath` first instead of
   the bundled `~/.c9/node/bin/node`. The VFS forks a child Node process
   (`node_modules/vfs-child/parent.js`) and file-search (`c9.vfs.server/filelist.js`, which
   uses only `nodeBin[0]`) needs a valid binary. Without this, find-in-files breaks.
2. **`scripts/setup-modern.sh`** — reproducible install: `npm install --omit=dev` then
   restore the vendored modules npm deletes (`amd-loader`, `architect`, `c9`, `smith`,
   `treehugger`, `connect-architect`, `frontdoor`, `kaefer`, `msgpack-js`).
3. **`scripts/start-modern.sh`** — launch bound to `127.0.0.1` only.

## How to run

```bash
scripts/setup-modern.sh      # once, after clone
scripts/start-modern.sh      # http://127.0.0.1:8181/ide.html
```

## Known issues / remaining work

| Area | Status | Note |
|------|--------|------|
| Server boot (Node 24) | ✅ works | only a benign `util._extend` deprecation warning |
| `/ide.html` + static + require | ✅ works | dev CDN compiles modules on the fly |
| In-browser runtime (~101 client plugins, Ace, VFS websocket) | ⚠️ unverified | needs a real Chrome + DevTools smoke test |
| File tree / file ops | ⚠️ fixed in config, verify in browser | nodeBin fix above |
| File search (nak) | ⚠️ depends on nodeBin fix | uses `nodeBin[0]` directly |
| LESS skin compile | ❌ 500 on some skins | modern `less` rejects undefined var `@collab-chat-font-size`; needs LESS var fixes |
| Terminal | ❌ degraded | needs Node-24 `node-pty` + `tmux` (`brew install tmux`) |
| Dependencies | ❌ EOL | `connect@2.12`, `engine.io/ws@1.x`, `qs@0.6.6`, `ejs@1.0`, `uglify-js@2.6`, etc. — live CVEs, never patched upstream |
| `node_modules` committed to git | ⚠️ defeats `npm audit`/upgrade | by design upstream; restructure before any dep modernization |

## ⚠️ Security model (read before exposing anything)

The standalone build is **remote-code-execution by design**:
- VFS is rooted at your home dir + a full terminal → any reachable client gets a shell.
- `api.authenticate` is a **stub that always returns an admin user**; `--auth`/`-a` is
  optional Basic Auth on the command line; `-a :` forces **no login**.
- No TLS by default, no WebSocket Origin/CSRF check.

**Keep it on `127.0.0.1` only.** Anything beyond localhost requires, first: real
auth+authz, TLS-by-default, strict Origin/host pinning + CSRF on the engine.io upgrade,
and per-workspace OS sandboxing (container/namespaces, non-root, scoped VFS root, resource
limits). Also review `LICENSE-COMMERCIAL-USE` before redistributing a fork.

## Strategic options for "continued development"

| Option | What | Effort | Verdict |
|--------|------|--------|---------|
| **A. Pin & freeze** | Run as-is on pinned Node 24 + the surgical fixes above; touch no deps/build/arch. A working reference to study and harvest. | days | Done-ish (this fork) |
| **B. Incremental in-place** | Keep architect + APF; grind through dep swaps, removed APIs, transports, auth. | months | ⚠️ Trap — ends still-legacy on abandoned APF UI framework |
| **C. Adopt a maintained base** | Build your suite on code-server / openvscode-server / Theia; port only the genuinely unique c9 bits. Keep c9-core as reference. | weeks | ✅ Recommended for a *tool suite* |
| **D. Rewrite the shell, keep Ace** | New stack (Vite/esbuild, modern UI, LSP, CRDT collab) around Ace; optionally keep the architect plugin model. | quarters–year+ | Only if the architect plugin model *is* the product |

**Why B is a trap:** the IDE UI rests on **APF** (a custom XML-widget framework abandoned
~2011, no upstream) and an AMD/`uglify-js@2.6` build that can't even parse ES6. You'd spend
months and still be on a dead UI framework with an ES5 ceiling. The cleanly separable asset
is **Ace** (vendored 1.3.3); the lock-in is the shell, not the editor.

## Recommended next steps

1. Browser smoke test: open `http://127.0.0.1:8181` in Chrome with DevTools, watch the
   ~101 client plugins boot, confirm Ace renders and the VFS websocket connects.
2. Decide deployment target (localhost-only vs multi-user) — this gates the security work.
3. 1–2 week spike: stand up code-server/openvscode-server and compare against what c9
   uniquely gives you, then choose Option C vs D.
