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

### async 0.9 → 3.2.6 ✅ (clears CVE-2021-43138 prototype pollution)
- async@3 keeps the `forEach`/`forEachSeries` aliases, so the only **real** breakage was
  `async.filterSeries` in `c9.vfs.standalone/standalone.js`: its callback signature changed
  `cb(bool)` → `cb(err, bool)`. Unfixed, `/test/all.json` returned `["define("]` instead of the
  file list. Fixed; verified `/test/all.json` is a real 139-item array. `forEach`→`each` canonicalized
  at 5 sites (cosmetic/future-proof). The browser shim `c9.nodeapi/async.js` left untouched.

### optimist → yargs@17 ✅ (drops minimist@0.0.10 / CVE-2020-7598)
- `require("optimist")` → `require("yargs/yargs")` factory (server.js, scripts, cli.js). **Boot trap
  handled:** yargs `process.exit()`s on `--help`/`--version` during `.argv` → added `.help(false).version(false)`
  in server.js to keep the manual help path. cli.js `.check(fn)` wrapped to `return true` (yargs treats
  a falsy return as failure). Verified: boots via yargs argv, `optimist` + `minimist@0.0.10` removed, `bin/c9 --help` works.

### mocha 1.8 → 10.8 + chai 1.5 → 4.5 ✅ (EOL test deps)
- package.json-only; kept in `dependencies` (served raw to the in-IDE test runner at `/static/lib/{mocha,chai}`).
  chai stays at 4 (chai 5 is ESM-only, breaks require/AMD). Verified both serve 200.

### root ws 1.0.1 → 8 ✅
- Only consumed by the (dead-code) `netproxy-ws.js` debug helper; migrated its `message (data,flags)`→`(data,isBinary)`
  and a never-firing `'end'`→`'close'` handler. The bump forces `engine.io`/`engine.io-client` to keep their
  **own nested ws@1.0.1**, so the live websocket transport is byte-unchanged (verified).

### npm audit enabled + CVE sweep ✅ (36 → 23 vulnerabilities)
- A committed `package-lock.json` makes `npm audit` work (`npm install --package-lock-only --omit=dev`
  generates it without touching the committed node_modules). Run: `npm audit --omit=dev`.
- **less 2 → 4** (reversing the earlier "defer" — the audit showed it's NOT cosmetic): less@2 pulled
  `request@2.81.0` as an optional dep, dragging in a **critical SSRF + ~10 transitive CVEs**
  (form-data critical, boom, hawk, hoek, cryptiles, sntp, har-validator, tough-cookie, uuid). less@4
  drops all of it. Applied the validated `build.js` rewrite (`less.render()` with `math:'always'` +
  `javascriptEnabled:true`). Verified: shipped skins (`dark.css`, `flat-light.css`) compile to 200.
- **tmp 0.2.4 → ^0.2.7** — the Tier-1 bump to 0.2.4 wasn't enough; the path-traversal fix landed in 0.2.6.
- **connect 2.12 → 2.30.2 REVERTED** — npm's "fixAvailable" suggestion is a net loss (23 → **37**);
  newer connect 2.x bundles *more* vulnerable transitives. The real fix is connect→express (Tier 3).
- **Result: 36 → 23** (criticals 4 → 2). The 2 remaining criticals (`engine.io-client`,
  `xmlhttprequest-ssl`) and most of the 23 are **gated behind the deferred Tier-3 migrations** —
  nothing else is safely fixable without a breaking change.

### connect 2.12 → connect 3.7 + extracted middleware ✅ (Tier 3 — clears the connect CVE cluster)
- connect@3 removed all bundled middleware + `connect/lib/utils`. Migrated via a **getModule()
  compatibility shim** in `connect-plugin.js` so **zero consumer files changed**: `getModule()`
  returns an enriched `connectModule` mapping the legacy names to the extracted packages —
  `createServer`→connect, `static`→serve-static, `compress`→compression, `favicon`→serve-favicon,
  `basicAuth`→a **constant-time** (basic-auth + `crypto.timingSafeEqual`) inline middleware, plus
  cookieParser/urlencoded/json/query insurance for the unwired group-C plugins.
- Provider lines 87-89: `connect.cookieParser/urlencoded/json` → cookie-parser + body-parser
  (`extended:true`, `limit:1mb` to match connect 2.12 semantics). New `connect-utils-shim.js`
  replaces the removed `connect/lib/utils`. Live static path = **serve-static (traversal-safe)** via the shim.
- deps: `connect ^3.7.0` + cookie-parser/body-parser/compression/serve-static/serve-favicon/basic-auth.
- **Vendored-toplevel** edits (connect-plugin.js, the new shim, middleware/static.js) were committed
  *before* the Docker build (the Dockerfile git-restores `node_modules/connect-architect`).
- **Verified in Docker:** 401 + `WWW-Authenticate` challenge; 200 with creds; **wrong creds → 401, no
  crash** (constant-time); static serves 200, **`../` + encoded traversal both blocked (404)**;
  "Cloud9 is up and running"; connect@3.7.0 single copy.

### Audit progress: 36 → 23 → **15** vulnerabilities
Cleared the connect cluster (connect XSS, qs, mime, send, cookie, cookie-signature, fresh, multiparty).
Remaining 15 are gated as below; the 2 criticals (engine.io-client, xmlhttprequest-ssl) are the transport.

### engine.io 1.6.9 → 6.x transport migration ✅ (Tier 3 — the VFS lifeline; clears BOTH remaining criticals)
The deferred/quarantined one — done with a headless end-to-end gate. Only **3 runtime edits** (kaefer/smith needed NO code change):
- `package.json`: `engine.io` + `engine.io-client` → `^6` (lockstep — EIO3 server + EIO4 client, or a stale bundle, = silent kaefer reconnect loop).
- `vfs.js`: added `allowEIO3: true` (staged compat so cached EIO3 clients keep working — makes the bump **non-destructive**) and `maxHttpBufferSize: 1e8` (v6 silently dropped the default from ~95MB to 1MB — would have silently killed large file ops).
- `statics.js`: `engine.io-client/engine.io.js` → `.../dist/engine.io.js` (v6 moved the served UMD bundle; the old path throws `ERR_PACKAGE_PATH_NOT_EXPORTED` and the /engine.io mount never registers).
- A wrong edit (`new eio.Socket()` in vfs_client.js) was **empirically refuted** by the analysis (the served UMD export is the callable `eio(opts)` with no `.Socket`) — so it is NOT in the change set.
- **Bonus modern-Node fix** in `vfs-socket` (`consumer.js` + `worker.js`): `stream.hasOwnProperty("readable")` → `"readable" in stream` — on modern Node `readable`/`writable` are prototype getters, so the old check never propagated the flag and broke stream proxying with native Node streams.
- **Headless E2E** (`scripts/vfs-headless-test.js`): broker REST → engine.io@6 handshake → kaefer → smith → vfs-socket → **real fs mkfile/readfile/stat + process spawn**, **PASS on BOTH polling and websocket**. Run: `docker cp` it in, then `docker exec ... node scripts/vfs-headless-test.js`.
- **Residual (browser-only):** the live `/ide.html` mini_require AMD load of the served bundle. Keep `allowEIO3:true` until a browser smoke confirms connect + open/save a file + run a terminal command, then it may be flipped to `false`.

### Audit progress: 36 → 23 → 15 → **5** vulnerabilities · **0 critical**
The transport cluster cleared both criticals (engine.io-client, xmlhttprequest-ssl). The irreducible remaining 5 are test-only / git-dep:

## Known gaps / next — the remaining 5 CVEs (irreducible tail)
- **mocha + serialize-javascript** — test-only (moderate), no runtime exposure.
- **glob + minimatch** — deep transitive of old test/build deps.
- **tern** — the git-sourced JS-intelligence fork; no upstream fix (its real modernization is an LSP re-architecture).
- Earlier known gaps (cosmetic skin scope, full `file:`-deps `npm ci` restructure) remain optional.
- **~10 → connect→express 4 (Tier 3):** connect XSS + its bundled mime/qs/send/cookie/accepts/negotiator/fresh/ms.
- **~8 → engine.io/ws transport migration (DEFERRED, quarantined):** engine.io, engine.io-client,
  xmlhttprequest-ssl, ws, parsejson, parseuri, debug(transitive). The VFS lifeline — bump in lockstep or not at all.
- **uglify-js 2 → terser (Tier 3):** serialize-javascript RCE.
- **tern (git dep, Tier 3):** no upstream; replace with an LSP path eventually.
- **deep transitive / test-only:** glob, minimatch, multiparty, ajv, mocha — clear as their parents move.
- **Optional later:** full `file:`-deps restructure so `npm ci` (not just `npm install`) works in CI. send (`.root()`→options), async 0.9→3, optimist→yargs, ejs 1→3,
  mocha/chai, root `ws`→8 (the netproxy helper only), less 2→4 (fixes the skin 500), and the
  git-dep / committed-`node_modules` supply-chain restructure so `npm ci`/`npm audit` work.
- **Tier 3 (risky, dedicated efforts):** connect 2→express 4, uglify-js 2→terser,
  acorn 2→8, `crypto.createCipher`→`createCipheriv`, and — deferred/quarantined — the
  engine.io/ws/smith **transport** (VFS lifeline; never bump half of a wire protocol).

## Security (unchanged by this work)
Still RCE-by-design. Keep it on `127.0.0.1` / behind the Docker basic-auth entrypoint + TLS.
None of these bumps make it safe to expose raw to the internet.
