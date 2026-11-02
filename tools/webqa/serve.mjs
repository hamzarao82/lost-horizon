// Throwaway static server for the Godot web export (no dependencies).
// usage: node tools/webqa/serve.mjs [dir=site-assets/play] [port=0]  -> prints PORT=<n>
import { createServer } from 'node:http'
import { readFile, stat } from 'node:fs/promises'
import { join, extname, resolve, sep } from 'node:path'

const root = resolve(process.argv[2] ?? 'site-assets/play')
const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png',
  '.json': 'application/json',
}
const server = createServer(async (req, res) => {
  try {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname)
    if (p.endsWith('/')) p += 'index.html'
    const file = resolve(join(root, p))
    if (!file.startsWith(root + sep) && file !== root) { res.writeHead(403).end(); return }
    await stat(file)
    const body = await readFile(file)
    res.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' })
    res.end(body)
  } catch { res.writeHead(404).end('not found') }
})
server.listen(Number(process.argv[3] ?? 0), '127.0.0.1', () => console.log('PORT=' + server.address().port))
