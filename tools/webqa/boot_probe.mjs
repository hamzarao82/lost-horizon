// Boot timing probe for the Godot web build (real Chromium via patchright).
//   node tools/webqa/boot_probe.mjs --url http://127.0.0.1:PORT/ --profile desktop|mobile --label name [--lock]
// Prints Godot's BOOT_* console markers with browser-side timestamps, main-thread long tasks, memory,
// time to playable (BOOT_PHASE DONE) and, with --lock, the first-click pointer-lock behaviour.
import { createRequire } from 'node:module'
import { readdirSync, mkdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { execSync } from 'node:child_process'

const OUT = process.env.WEBQA_OUT ?? 'C:/Users/SCS/AppData/Local/Temp/claude/C--Users-SCS/4576ce53-cb85-47a2-9ca4-82253bc04267/scratchpad/webperf'
mkdirSync(OUT, { recursive: true })
const argv = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
  if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : 'true'])
  return acc
}, []))
const URL_ = argv.url, PROFILE = argv.profile ?? 'desktop', LABEL = argv.label ?? PROFILE, MOBILE = PROFILE === 'mobile'
const base = join(homedir(), '.vscode/extensions')
const dirs = readdirSync(base).filter((d) => d.startsWith('danielsanmedium.dscodegpt-')).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
const chromium = createRequire(join(base, dirs[dirs.length - 1], 'standalone') + '/')('patchright').chromium
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const browser = await chromium.launch({ headless: true, channel: 'chromium', args: ['--no-sandbox', '--disable-dev-shm-usage', '--autoplay-policy=no-user-gesture-required'] })
const ctx = await browser.newContext({
  locale: 'en-US', viewport: MOBILE ? { width: 800, height: 360 } : { width: 1280, height: 720 }, hasTouch: MOBILE, isMobile: MOBILE, deviceScaleFactor: 1,
  userAgent: MOBILE ? 'Mozilla/5.0 (Linux; Android 14; Redmi K80) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36' : undefined,
})
const page = await ctx.newPage()
await page.addInitScript(() => {
  window.__wasm = {}
  for (const k of ["compileStreaming","instantiateStreaming","compile","instantiate"]) {
    const orig = WebAssembly[k]; if (!orig) continue
    WebAssembly[k] = function (...a) { const t = performance.now(); window.__wasm[k + "_start"] = Math.round(t)
      const p = orig.apply(this, a); p.then(() => { window.__wasm[k + "_end"] = Math.round(performance.now()) }); return p }
  }
  window.__long = []
  try { new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__long.push([Math.round(e.startTime), Math.round(e.duration)]) }).observe({ type: 'longtask', buffered: true }) } catch {}
  window.__lock = { change: 0, error: 0 }
  document.addEventListener('pointerlockchange', () => window.__lock.change++)
  document.addEventListener('pointerlockerror', () => window.__lock.error++)
})
const t0 = Date.now()
const marks = [], errors = [], lines = []
page.on('console', (m) => {
  const t = m.text(); const at = Date.now() - t0
  if (/^BOOT_/.test(t)) { marks.push([at, t]); console.log(`  [${(at / 1000).toFixed(1)}s] ${t}`) }
  if (['error'].includes(m.type())) errors.push(t.slice(0, 200))
})
page.on('pageerror', (e) => errors.push(String(e).slice(0, 200)))
await page.goto(URL_, { waitUntil: 'domcontentloaded', timeout: 120000 })
const domAt = Date.now() - t0
let doneAt = null
let seen = 0
for (let i = 0; i < 1400 && doneAt === null; i++) {
  const arr = await page.evaluate(() => window.__boot ?? [], undefined, undefined, false).catch(() => [])
  for (; seen < arr.length; seen++) { marks.push([Date.now() - t0, arr[seen]]); console.log(`  [${((Date.now() - t0) / 1000).toFixed(1)}s] ${arr[seen]}`) }
  if (arr.some((l) => l.startsWith("BOOT_PHASE DONE"))) doneAt = Date.now() - t0; else await sleep(500)
}
const wsMB = () => { try { return Math.round(parseFloat(execSync(`powershell -NoProfile -Command "(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*chromium-1248*' } | Measure-Object WorkingSet64 -Sum).Sum / 1MB"`, { encoding: 'utf8' }))) } catch { return null } }
const res = { label: LABEL, profile: PROFILE, domContentLoadedS: +(domAt / 1000).toFixed(1), playableS: doneAt === null ? null : +(doneAt / 1000).toFixed(1), errors: errors.slice(0, 5) }
if (doneAt !== null) {
  await sleep(2500)
  res.memAfterBootMB = wsMB()
  if (argv.lock) {
    // the intro (fresh game) is skippable by click; then the next click must capture the pointer
    const c = page.locator('canvas'); await sleep(1500)
    const clickAt = async (n) => { await page.mouse.click(640, 360); await sleep(900); return await page.evaluate(() => ({ el: !!document.pointerLockElement, change: window.__lock.change, error: window.__lock.error }), undefined, undefined, false).catch(() => null) }
    res.afterClick1 = await clickAt(1); res.afterClick2 = await clickAt(2); res.afterClick3 = await clickAt(3)
  }
}
res.wasm = await page.evaluate(() => window.__wasm, undefined, undefined, false).catch(() => ({}))
res.longTasks = await page.evaluate(() => window.__long, undefined, undefined, false).catch(() => [])
const lt = res.longTasks ?? []
res.mainThreadBlockedS = +(lt.reduce((s, [, d]) => s + d, 0) / 1000).toFixed(1)
res.worstStallMs = lt.length ? Math.max(...lt.map(([, d]) => d)) : 0
res.stallsOver1s = lt.filter(([, d]) => d >= 1000).map(([s, d]) => `${(s / 1000).toFixed(1)}s+${d}ms`)
res.marks = marks.map(([t, m]) => `${(t / 1000).toFixed(1)}s ${m}`)
writeFileSync(join(OUT, `${LABEL}.json`), JSON.stringify(res, null, 1))
console.log(JSON.stringify({ ...res, marks: undefined, longTasks: undefined }, null, 1))
await browser.close()
