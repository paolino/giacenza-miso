// Minimal static file server for the built wasm page (public/).
// Usage: node scripts/serve.mjs [port] [dir]
import http from "node:http";
import { promises as fs } from "node:fs";
import path from "node:path";

const port = Number(process.argv[2] ?? 8123);
const root = path.resolve(process.argv[3] ?? "public");

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".wasm": "application/wasm",
  ".ico": "image/x-icon",
};

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://localhost:${port}`);
    let file = path.join(root, decodeURIComponent(url.pathname));
    if (file.endsWith(path.sep)) file = path.join(file, "index.html");
    const body = await fs.readFile(file);
    res.writeHead(200, {
      "Content-Type": types[path.extname(file)] ?? "application/octet-stream",
      "Content-Length": body.length,
    });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end("not found");
  }
});

server.listen(port, () => console.log(`serving ${root} on http://localhost:${port}`));
