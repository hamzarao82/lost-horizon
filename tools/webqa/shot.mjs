// Screenshot of the running web build after boot: node tools/webqa/shot.mjs --url http://127.0.0.1:PORT/ --out file.png
import { createRequire } from 'node:module'
import { readdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
const argv = Object.fromEntries(process.argv.slice(2).reduce((a, x, i, all) => { if (x.startsWith('--')) a.push([x.slice(2), all[i + 1]]); return a }, []))
const base = join(homedir(), '.vscode/extensions')
const dirs = readdirSync(base).filter((d) => d.startsWith('danielsanmedium.dscodegpt-')).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
const chromium = createRequire(join(base, dirs[dirs.length - 1], 'standalone') + '/')('patchright').chromium
const browser = await chromium.launch({ headless: true, channel: 'chromium', args: ['--no-sandbox', '--autoplay-policy=no-user-gesture-required'] })
const page = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage()
await page.addInitScript(() => {})
await page.goto(argv.url, { waitUntil: 'domcontentloaded' })
for (let i = 0; i < 400; i++) {
  const arr = await page.evaluate(() => window.__boot ?? [], undefined, undefined, false).catch(() => [])
  if (arr.some((l) => l.startsWith('BOOT_PHASE DONE'))) break
  await new Promise((r) => setTimeout(r, 500))
}
await new Promise((r) => setTimeout(r, 2500))
await page.mouse.click(640, 360)
await new Promise((r) => setTimeout(r, 3000))
await page.screenshot({ path: argv.out })
console.log('saved', argv.out)
await browser.close()
