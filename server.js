#!/usr/bin/env node
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = Number(process.env.DRAW_PORT || 8114);
const ROOT = __dirname;
const META_FILE = path.join(ROOT, "exports-meta.json");
const MAX_BYTES = 12 * 1024 * 1024; // 12MB

function readMeta() {
  try {
    return JSON.parse(fs.readFileSync(META_FILE, "utf8"));
  } catch (_) {
    return { next: 1 };
  }
}

function writeMeta(meta) {
  fs.writeFileSync(META_FILE, JSON.stringify(meta));
}

function nextImageName() {
  const meta = readMeta();
  let n = Math.max(1, Number(meta.next) || 1);
  // Skip names that somehow already exist
  for (let guard = 0; guard < 100000; guard++) {
    const name = "image" + n + ".png";
    if (!fs.existsSync(path.join(ROOT, name))) {
      meta.next = n + 1;
      writeMeta(meta);
      return name;
    }
    n += 1;
  }
  throw new Error("Could not allocate image name");
}

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > MAX_BYTES) {
        reject(Object.assign(new Error("Payload too large"), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", "http://127.0.0.1");

  if (req.method === "OPTIONS" && url.pathname === "/api/export") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    res.end();
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/export") {
    try {
      const buf = await readBody(req);
      if (!buf.length || buf[0] !== 0x89 || buf.toString("ascii", 1, 4) !== "PNG") {
        sendJson(res, 400, { error: "Expected a PNG body" });
        return;
      }
      const name = nextImageName();
      fs.writeFileSync(path.join(ROOT, name), buf);
      sendJson(res, 200, {
        name,
        url: "/" + name,
        absoluteUrl: "https://draw.63616c6c616e313031.com/" + name,
      });
    } catch (err) {
      const status = err && err.status ? err.status : 500;
      sendJson(res, status, { error: err.message || "Export failed" });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/health") {
    sendJson(res, 200, { ok: true });
    return;
  }

  sendJson(res, 404, { error: "Not found" });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log("draw export listening on 127.0.0.1:" + PORT);
});
