# Modernization log

Tracking the in-place modernization of c9-core to run cleanly & sustainably on the latest
Node / Ubuntu. Plan tiers come from the dependency + Node-compat analysis (see `MODERNIZE.md`
for the strategic picture). Every change is gated by `scripts/verify-docker.sh` (clean Linux
build + the IDE still serves) plus targeted functional smokes.

## Node baseline
- `package.json` → `"engines": { "node": ">=22 <25" }`, `"os": ["linux","darwin"]`
- `.nvmrc` → `24` (matches the Dockerfile base `node:24-bookworm-slim`)

## Tier 1 — DONE ✅ (verified: clean Docker build + `/ide.html` 200 + VFS write/read roundtrip)

### Dependency bumps (clear real CVEs; all confirmed ES5-safe for the browser bundle)
| dep | from | to | clears |
|-----|------|----|--------|
| mime | ~1.2.9 | 1.6.0 | CVE-2017-16138 (ReDoS) |
| qs | 0.6.6 | ^6.13.0 | CVE-2014-7191, CVE-2017-1000048 (proto-pollution/DoS) |
| debug | ~0.7.4 | ^4.4.0 | CVE-2017-16137 |
| mkdirp | ~0.3.5 | 0.5.6 (cap <1, keep callback API) | minimist CVE-2020-7598 |
| tmp | ~0.0.20 | 0.2.4 | symlink arbitrary-write advisory |
| through | 2.2.0 | 2.3.8 | — (freshen) |
| rusha | 0.8.5 | 0.8.14 | — (freshen) |
| form-data | ~0.2.0 | **removed** | vestigial pin (request uses nested copy) |
| base64id | ~0.1.0 | **removed** | transitive of engine.io |

### Node-API codemods (future-proof against hard removals; mechanical, syntax-checked)
- `vfs-local/localfs.js`: `require("constants")` → `require("fs").constants` (DEP0008)
- `new Buffer(...)` → `Buffer.from/alloc` on executed sites: `localfs.js:941`,
  `preview.handler.js:335`, `architect-build/copy.js:13`, `vfs-http-adapter/multipart.js:11` (DEP0005)
- `jsonalyzer/simple_watch.js`: `path.existsSync` → `fs.existsSync` (path.existsSync was REMOVED)

### Bug fixed (caught by the VFS smoke, not by `/ide.html`)
- **`vfs-local/localfs.js:905` — file-save was broken on modern Node.** It called
  `fs.open(path, flags, mode, options, cb)`; modern `fs.open` has no `options` param, so Node
  took the options *object* as the callback and threw `ERR_INVALID_ARG_TYPE`. Removed the stray
  arg → `fs.open(path, flags, mode, cb)`. **Verified:** a write→read roundtrip through the VFS
  now succeeds and the file lands on the mounted volume.

## Terminal — DONE ✅ (node-pty on Node 24)
- `package.json` → added `node-pty@^1.1.0` (Microsoft's maintained successor; builds from source —
  python3/make/g++ already in the image).
- `vfs-local/localfs.js` → added `node-pty` to the pty require list (was only `node-pty-prebuilt`
  / `pty.js`, both ancient and unbuildable on Node 24). Same `.spawn` API, so no other changes.
- **Verified in the Linux image:** node-pty 1.1.0 compiles, the "unable to initialize pty.js"
  warning is gone, and `pty.spawn("bash", …)` runs a command and returns its output. tmux 3.3a
  present (c9 wraps it). Final browser check: open a Terminal pane in the IDE and type a command.

## Tier 2 — IN PROGRESS

### send 0.1.4 → 0.19.0 ✅ (clears the 0.1.x directory-traversal CVE)
- The chained `.root(dir)` builder was removed; moved to the options object `send(req, path, {root})`
  at `c9.static/cdn.js` (×2) and `architect-build/transform.js`. Verified `/static` still serves.

### ejs 1.0 → 3.1 ✅ (clears the ejs template-injection CVE class)
- `ejs.filters` removed → `JSONToJS` is now passed to templates as a local function
  (`connect-architect/.../render-ejs.js`); templates use `<%- JSONToJS(x) %>` not `<%-: x | JSONToJS %>`.
- `<% include x %>` → `<%- include('x') %>`; `<%-:` filter-mode → `<%-` across `standalone.html.ejs`,
  `load-screen.ejs`, `flat-load-screen.html`.
- **Gotcha fixed:** ejs@1's textual include shared lexical scope; ejs@3's `include()` only gets the
  passed data. So `theme`/`isDark`/`staticPrefix` had to be passed explicitly into the nested
  includes (with a `/static` fallback for `staticPrefix`, which the render data never supplied).
- Verified: `/ide.html` 200, the `var plugins = [...]` array renders, the load-screen include chain
  renders. (Note: editing the vendored `render-ejs.js` requires committing it so the Dockerfile's
  git-restore of `node_modules/connect-architect` keeps the change.)

## Known gaps / next
- **Tier 2 (remaining):** async 0.9→3, optimist→yargs, mocha/chai, root `ws`→8 (netproxy helper),
  less 2→4 + the skin scope fix (cosmetic — `chat.css` theme vars), and the
  git-dep / committed-`node_modules` supply-chain restructure so `npm ci`/`npm audit` work. send (`.root()`→options), async 0.9→3, optimist→yargs, ejs 1→3,
  mocha/chai, root `ws`→8 (the netproxy helper only), less 2→4 (fixes the skin 500), and the
  git-dep / committed-`node_modules` supply-chain restructure so `npm ci`/`npm audit` work.
- **Tier 3 (risky, dedicated efforts):** connect 2→express 4, uglify-js 2→terser,
  acorn 2→8, `crypto.createCipher`→`createCipheriv`, and — deferred/quarantined — the
  engine.io/ws/smith **transport** (VFS lifeline; never bump half of a wire protocol).

## Security (unchanged by this work)
Still RCE-by-design. Keep it on `127.0.0.1` / behind the Docker basic-auth entrypoint + TLS.
None of these bumps make it safe to expose raw to the internet.
