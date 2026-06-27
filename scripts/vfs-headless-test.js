#!/usr/bin/env node
// HEADLESS end-to-end VFS transport test. Run INSIDE the running container via docker exec.
// Version-agnostic: the SAME script proves EIO3 on today's image and EIO4 after the bump,
// which is exactly how it proves server+client are version-LOCKED. A handshake TIMEOUT here
// is the clean signal of a half-upgrade (instead of kaefer's silent reconnect loop).
// Do NOT commit into the image; copy it in at test time (docker cp).
"use strict";
require("amd-loader");
var http = require("http"), https = require("https"), Stream = require("stream");
var assert = require("assert"), fs = require("fs"), urlmod = require("url");

var BASE = process.env.C9_BASE || ("http://127.0.0.1:" + (process.env.PORT || 8181));
var USER = process.env.C9_USERNAME || "cloud9";
var PASS = process.env.C9_PASSWORD || "";
var PID  = process.env.C9_PID || "1";
var WORKSPACE = process.env.C9_WORKSPACE || "/workspace";
var TRANSPORT = process.env.C9_TRANSPORT || "polling,websocket"; // run once with polling, once with websocket
var AUTH = "Basic " + Buffer.from(USER + ":" + PASS).toString("base64");

var eio = require("engine.io-client");
var Socket = eio.Socket || eio;            // v6 node CJS exposes .Socket; v1 is callable AND has .Socket
var kaefer = require("kaefer");            // node index.js -> { Server, connectClient, version, ... }
var connectClient = kaefer.connectClient;
var PROTOCOL = kaefer.version.protocol;    // = 13; broker (vfs.server.js) rejects any mismatch
var smith = require("smith");
var Consumer = require("vfs-socket/consumer").Consumer;

var u = urlmod.parse(BASE), lib = u.protocol === "https:" ? https : http;
function fail(m) { console.error("FAIL:", m); process.exit(1); }

function brokerPost(cb) {
  var body = JSON.stringify({ version: String(PROTOCOL) });
  var r = lib.request({
    method: "POST", hostname: u.hostname, port: u.port, path: "/vfs/" + PID, rejectUnauthorized: false,
    headers: { Authorization: AUTH, "Content-Type": "application/json",
               "Content-Length": Buffer.byteLength(body), Accept: "application/json" }
  }, function (res) {
    var d = ""; res.on("data", function (c) { d += c; });
    res.on("end", function () {
      if (res.statusCode !== 201 && res.statusCode !== 200) return fail("broker /vfs/" + PID + " -> " + res.statusCode + " " + d);
      var j; try { j = JSON.parse(d); } catch (e) { return fail("broker non-JSON: " + d); }
      if (!j.vfsid) return fail("no vfsid: " + d);
      cb(j.vfsid);
    });
  });
  r.on("error", function (e) { fail("broker error: " + e.message); });
  r.end(body);
}

brokerPost(function (vfsid) {
  console.log("broker OK vfsid=" + vfsid + " proto=" + PROTOCOL +
              " engine.io-client=" + require("engine.io-client/package.json").version +
              " transport=" + TRANSPORT);
  var socketPath = "/vfs/" + PID + "/" + vfsid + "/socket";
  var connection = connectClient(function () {
    return new Socket(BASE, {
      path: socketPath,
      transports: TRANSPORT.split(","),
      withCredentials: false,
      rejectUnauthorized: false,
      extraHeaders: { authorization: AUTH }   // /socket route has no authenticate() but passes global basicauth
    });
  });
  var timer = setTimeout(function () { fail("socket/handshake TIMEOUT (EIO mismatch / stale bundle / half-upgrade)"); }, 20000);
  connection.on("connect", function () {
    var c = new Consumer(); c.connectionTimeout = 8000;
    c.connect(new smith.EngineIoTransport(connection), function (err, vfs) {
      if (err) return fail("consumer connect: " + err);
      clearTimeout(timer);
      runChecks(vfs, vfsid);
    });
    c.on("error", function (e) { fail("consumer error: " + e); });
  });
  connection.connect();
});

function runChecks(vfs, vfsid) {
  var name = "headless-" + Date.now() + ".txt";
  var payload = "c9-headless-" + Date.now() + "-text-content-line\n"; // string (matches the browser file-save path)
  var _sent = false;
  var up = new Stream.Readable({ read: function () { this.push(_sent ? null : payload); _sent = true; } });
  up.setEncoding("utf8"); // emit STRING chunks over the wire, not Buffer (smith JSON-serializes a Buffer to {type:'Buffer'})
  vfs.mkfile("/" + name, { stream: up }, function (err) {   // NOTE: write op is "mkfile", not "writefile"
    if (err) return fail("mkfile: " + (err && (err.message || err.code) || JSON.stringify(err)));
    var onDisk; try { onDisk = fs.readFileSync(WORKSPACE + "/" + name); } catch (e) { return fail("not on disk: " + e.message); }
    assert.strictEqual(onDisk.toString("utf8"), payload, "disk != sent");
    console.log("PASS mkfile -> " + WORKSPACE + "/" + name + " (" + onDisk.length + "B real fs)");
    vfs.readfile("/" + name, {}, function (err, meta) {
      if (err) return fail("readfile: " + err);
      var g = []; meta.stream.on("data", function (c) { g.push(Buffer.from(c)); });
      meta.stream.on("end", function () {
        assert.strictEqual(Buffer.concat(g).toString("utf8"), payload, "readback mismatch");
        console.log("PASS readfile round-trip (" + Buffer.concat(g).length + "B)");
        vfs.stat("/" + name, {}, function (err, st) {
          if (err) return fail("stat: " + err);
          console.log("PASS stat: " + JSON.stringify(st));
          // Terminal/process stream check. For a fuller PTY proof (image has tmux + node-pty), swap
          // the spawn block for: vfs.pty("/bin/bash",{cols:80,rows:24},cb); write "echo hi\n" to meta.pty
          // and assert "hi" comes back on meta.pty data.
          vfs.spawn("/bin/echo", { args: ["hello-terminal"] }, function (err, m) {
            if (err) return fail("spawn: " + err);
            var out = ""; m.process.stdout.on("data", function (c) {
              if (c && c.type === "Buffer" && Array.isArray(c.data)) c = Buffer.from(c.data); // smith JSON-serializes binary process output to {type:'Buffer'}
              out += c.toString();
            });
            m.process.on("exit", function (code) {
              if (!/hello-terminal/.test(out)) return fail("spawn stdout: " + JSON.stringify(out));
              console.log("PASS spawn stdout=" + JSON.stringify(out.trim()) + " exit=" + code);
              cleanup(vfsid);
            });
          });
        });
      });
    });
  });
}

function cleanup(vfsid) {
  var r = lib.request({ method: "DELETE", hostname: u.hostname, port: u.port,
    path: "/vfs/" + PID + "/" + vfsid, rejectUnauthorized: false,
    headers: { Authorization: AUTH, Accept: "application/json" } },
    function (res) { res.resume(); fin(); });
  r.on("error", fin); r.end();
  function fin() { console.log("\nRESULT: PASS - headless VFS E2E (broker+socket+kaefer+smith+fs+spawn) transport=" + TRANSPORT); process.exit(0); }
}
