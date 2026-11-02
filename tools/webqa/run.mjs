// Real-browser QA for the Godot web build.
//   node tools/webqa/run.mjs --url <game url> --profile desktop|mobile --mode swift|gpu --label <name>
// Needs the patchright module that the browser-automation skill uses (VS Code extension "standalone").
// Screenshots and the JSON result go to the scratchpad webqa folder, never into the repo.
import { createRequire } from 'node:module'
import { readdirSync, existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { execSync } from 'node:child_process'

const OUT = process.env.WEBQA_OUT ??
  'C:/Users/SCS/AppData/Local/Temp/claude/C--Users-SCS/4576ce53-cb85-47a2-9ca4-82253bc04267/scratchpad/webqa'
mkdirSync(OUT, { recursive: true })

const argv = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
  if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : 'true'])
  return acc
}, []))
const URL_ = argv.url ?? 'https://hamzarao82.github.io/lost-horizon/play/'
const PROFILE = argv.profile ?? 'desktop'
const MODE = argv.mode ?? 'swift'
const LABEL = argv.label ?? `${PROFILE}-${MODE}`
const MOBILE = PROFILE === 'mobile'
const IDLE_S = Number(argv.idle ?? 10), ACTIVE_S = Number(argv.active ?? 10)

function resolvePatchright() {
  const base = join(homedir(), '.vscode/extensions')
  const dirs = readdirSync(base).filter((d) => d.startsWith('danielsanmedium.dscodegpt-'))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
  const root = join(base, dirs[dirs.length - 1], 'standalone') + '/'
  return createRequire(root)('patchright').chromium
}
const chromium = resolvePatchright()

// patchright evaluates in an isolated world by default; the frame counter and pointer lock live in the main world
const ev = (fn, arg) => page.evaluate(fn, arg, undefined, false)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const R = { label: LABEL, url: URL_, profile: PROFILE, mode: MODE, steps: {}, notes: [], shots: [] }
const log = (m) => console.log(`[${LABEL}] ${m}`)

const args = ['--no-sandbox', '--disable-dev-shm-usage', '--autoplay-policy=no-user-gesture-required']
if (MODE === 'gpu') args.push('--use-gl=angle', '--use-angle=d3d11', '--ignore-gpu-blocklist', '--enable-gpu-rasterization')
else args.push('--enable-unsafe-swiftshader')
const browser = await chromium.launch({ headless: true, channel: 'chromium', args })
const ctx = await browser.newContext({
  locale: 'en-US',
  viewport: MOBILE ? { width: 800, height: 360 } : { width: 1280, height: 720 },
  hasTouch: MOBILE, isMobile: MOBILE, deviceScaleFactor: 1,
  userAgent: MOBILE
    ? 'Mozilla/5.0 (Linux; Android 14; Redmi K80) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36'
    : undefined,
})
const page = await ctx.newPage()
await sleep(1500)
const baselineMB = (() => { try { return Math.round(parseFloat(execSync(`powershell -NoProfile -Command "(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*chromium-1248*' } | Measure-Object WorkingSet64 -Sum).Sum / 1MB"`, { encoding: 'utf8' }))) } catch { return null } })()
await page.addInitScript(() => {
  window.__raf = 0
  const loop = () => { window.__raf++; requestAnimationFrame(loop) }
  requestAnimationFrame(loop)
  window.__long = []
  try { new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__long.push([Math.round(e.startTime), Math.round(e.duration)]) }).observe({ type: 'longtask', buffered: true }) } catch {}
  window.__lock = { change: 0, error: 0 }
  document.addEventListener('pointerlockchange', () => window.__lock.change++)
  document.addEventListener('pointerlockerror', () => window.__lock.error++)
})

// --- network and console capture ---------------------------------------------------------
const consoleMsgs = [], pageErrors = [], failed = [], bad = [], headers = {}
page.on('console', (m) => { const line = `${m.type()}: ${m.text()}`.slice(0, 300); if (['error', 'warning'].includes(m.type())) consoleMsgs.push(line); if (process.env.WEBQA_VERBOSE) console.log('  console> ' + line) })
page.on('pageerror', (e) => pageErrors.push(String(e).slice(0, 300)))
page.on('requestfailed', (r) => failed.push(`${r.url()} ${r.failure()?.errorText}`))
page.on('response', (r) => {
  const u = r.url().split('?')[0]
  if (r.status() >= 400) bad.push(`${r.status()} ${u}`)
  if (/\.(wasm|pck|js|html)$/.test(u) || u.endsWith('/')) {
    const h = r.headers()
    headers[u.split('/').slice(-2).join('/')] = { status: r.status(), type: h['content-type'], enc: h['content-encoding'] ?? 'none', length: h['content-length'], cache: h['cache-control'] }
  }
})
const cdp = await ctx.newCDPSession(page)
await cdp.send('Network.enable')
let bytes = 0
cdp.on('Network.loadingFinished', (e) => { bytes += e.encodedDataLength })

// --- helpers -----------------------------------------------------------------------------
const t0 = Date.now()
const since = () => ((Date.now() - t0) / 1000).toFixed(1)
async function shot(name) {
  const p = join(OUT, `${LABEL}-${name}.png`)
  try { await page.screenshot({ path: p, timeout: 60000 }); R.shots.push(p); log(`screenshot ${name}`) } catch (e) { R.notes.push(`screenshot ${name} failed: ${e.message.slice(0, 120)}`) }
}
let shotFails = 0
async function jpegSize() { try { return (await page.screenshot({ type: 'jpeg', quality: 40, timeout: 20000 })).length } catch { shotFails++; return 0 } }
async function fps(seconds) {
  const a = await ev(() => window.__raf); const s = Date.now()
  await sleep(seconds * 1000)
  const b = await ev(() => window.__raf)
  return +((b - a) / ((Date.now() - s) / 1000)).toFixed(1)
}
function procMemMB() {
  try {
    const out = execSync(`powershell -NoProfile -Command "(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*chromium-1248*' } | Measure-Object WorkingSet64 -Sum).Sum / 1MB"`, { encoding: 'utf8' })
    return Math.round(parseFloat(out))
  } catch { return null }
}
async function idbKeys() {
  return ev(async () => {
    try {
      const dbs = (await indexedDB.databases?.()) ?? []
      const names = dbs.map((d) => d.name)
      const out = {}
      for (const name of names) {
        const db = await new Promise((res, rej) => { const q = indexedDB.open(name); q.onsuccess = () => res(q.result); q.onerror = () => rej(q.error) })
        for (const store of Array.from(db.objectStoreNames)) {
          const keys = await new Promise((res) => { const q = db.transaction(store).objectStore(store).getAllKeys(); q.onsuccess = () => res(q.result); q.onerror = () => res(['<error>']) })
          out[`${name}/${store}`] = keys.filter((k) => /save|settings|teleport|\.cfg|\.json/i.test(String(k)))
        }
        db.close()
      }
      return out
    } catch (e) { return { error: String(e) } }
  })
}
const hold = async (key, ms) => { await page.keyboard.down(key); await sleep(ms); await page.keyboard.up(key) }
async function touch(type, x, y) { await cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y, id: 1 }] }) }
async function tapAt(x, y) { await touch('touchStart', x, y); await sleep(70); await touch('touchEnd', x, y) }

// --- 1. load -----------------------------------------------------------------------------
log(`loading ${URL_} (${MODE}, ${PROFILE})`)
const nav = Date.now()
await page.goto(URL_, { waitUntil: 'domcontentloaded', timeout: 120000 })
R.steps.domContentLoadedS = +((Date.now() - nav) / 1000).toFixed(2)
await page.waitForSelector('canvas', { timeout: 120000 })
R.steps.canvasVisibleS = +((Date.now() - nav) / 1000).toFixed(2)
R.webglRenderer = await ev(() => {
  try { const c = document.createElement('canvas'); const gl = c.getContext('webgl2') || c.getContext('webgl'); const e = gl.getExtension('WEBGL_debug_renderer_info'); return gl.getParameter(e.UNMASKED_RENDERER_WEBGL) + ' | ' + gl.getParameter(e.UNMASKED_VENDOR_WEBGL) } catch (e) { return 'unavailable: ' + e }
})
R.userAgent = await ev(() => navigator.userAgent)
log(`renderer: ${R.webglRenderer}`)
await sleep(1500); await shot('1-engine-loading')

// game-scene heuristic: boot screen is a dark, simple frame, the arena is a large JPEG
const sizes = []
let base = null, gameAt = null
for (let i = 0; i < 160 && gameAt === null; i++) {
  const sz = await jpegSize(); sizes.push([+since(), sz])
  if (base === null) base = sz
  if (i > 2 && sz > Math.max(base * 2.2, 25000)) { gameAt = (Date.now() - nav) / 1000 }
  else await sleep(1500)
}
R.steps.gameVisibleS = gameAt === null ? null : +gameAt.toFixed(2)
R.steps.jpegSizeSeries = sizes.filter((_, i) => i % 3 === 0).slice(0, 30)
R.steps.transferredMBAtGame = +(bytes / 1048576).toFixed(2)
log(`game scene visible at ${R.steps.gameVisibleS}s (bytes so far ${R.steps.transferredMBAtGame} MB)`)
await shot('2-intro-or-first-scene')

// --- 2. first gesture: pointer lock, no swing --------------------------------------------
if (!MOBILE) {
  const box = await ev(() => { const r = document.querySelector('canvas').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })
  await page.mouse.move(box[0], box[1])
  await page.mouse.click(box[0], box[1])
  await sleep(120); await shot('3-right-after-first-click')
  await sleep(900)
  R.steps.pointerLockAfterFirstClick = await ev(() => document.pointerLockElement ? document.pointerLockElement.tagName + '#' + document.pointerLockElement.id : null)
  log(`pointer lock: ${R.steps.pointerLockAfterFirstClick}`)
  await page.keyboard.press('Enter'); await sleep(1500) // in case the intro is still showing
  R.steps.lockEventsAfterFirstClick = await ev(() => window.__lock)
  await page.mouse.click(box[0], box[1]); await sleep(1000)   // second click: should capture now
  R.steps.pointerLockAfterSecondClick = await ev(() => document.pointerLockElement ? document.pointerLockElement.tagName + '#' + document.pointerLockElement.id : null)
  R.steps.lockEventsAfterSecondClick = await ev(() => window.__lock)
  log('pointer lock after 2nd click: ' + R.steps.pointerLockAfterSecondClick)
} else {
  await tapAt(400, 180); await sleep(1500)
}
await shot('4-beach-start')
R.steps.jsHeapMB = await ev(() => performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null)
R.steps.chromeWorkingSetMB_afterLoad = procMemMB()

// --- 3. FPS idle / active ------------------------------------------------------------------
R.steps.fpsIdle = await fps(IDLE_S)
log(`idle fps ${R.steps.fpsIdle}`)
const end = Date.now() + ACTIVE_S * 1000
let k = 0, shotMove = false
if (!MOBILE) {
  await page.keyboard.down('KeyW'); await page.keyboard.down('ShiftLeft')
  const a = await ev(() => window.__raf); const s = Date.now()
  while (Date.now() < end) {
    k++
    if (k % 2 === 0) await page.keyboard.press('Space')
    await page.mouse.click(640, 360, { button: k % 5 === 0 ? 'right' : 'left' })
    if (k === 6 && !shotMove) { shotMove = true; await shot('5-moving-attacking') }
    await sleep(450)
  }
  const b = await ev(() => window.__raf)
  R.steps.fpsActive = +((b - a) / ((Date.now() - s) / 1000)).toFixed(1)
  await page.keyboard.up('KeyW'); await page.keyboard.up('ShiftLeft')
} else {
  // stick on the left half, buttons bottom right (logical 1600x720 shown at 800x360 = scale 0.5)
  await touch('touchStart', 130, 250)
  const a = await ev(() => window.__raf); const s = Date.now()
  while (Date.now() < end) {
    k++
    await touch('touchMove', 130 + 25 * Math.sin(k), 250 - 60)
    await sleep(450)
    if (k === 5) await shot('5-touch-stick-held')
  }
  const b = await ev(() => window.__raf)
  R.steps.fpsActive = +((b - a) / ((Date.now() - s) / 1000)).toFixed(1)
  await touch('touchEnd', 130, 190)
  for (const [name, x, y] of [['attack', 705, 330], ['jump', 755, 315], ['heavy', 725, 280], ['dodge', 770, 265], ['heal', 665, 285], ['lock', 635, 330], ['tele', 675, 235], ['spin', 605, 285]]) { await tapAt(x, y); await sleep(350) }
  await shot('6-after-button-taps')
}
log(`active fps ${R.steps.fpsActive}`)
R.steps.chromeWorkingSetMB_afterPlay = procMemMB()
R.steps.jsHeapMB_afterPlay = await ev(() => performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null)

if (!MOBILE) {
  // --- 4. other keys ---------------------------------------------------------------------
  for (const key of ['KeyE', 'KeyR', 'ControlLeft', 'KeyC', 'KeyT', 'KeyQ']) { await page.keyboard.press(key); await sleep(400) }
  await sleep(700); await shot('7-after-keys-E-R-Ctrl-C-T-Q')

  // --- 5. pause menu, save, persistence --------------------------------------------------
  await page.keyboard.press('KeyP'); await sleep(900); await shot('8-pause-menu')
  await page.keyboard.press('ArrowDown'); await sleep(250)   // Resume -> Save
  await page.keyboard.press('Enter'); await sleep(1500)
  R.steps.idbAfterSave = await idbKeys()
  log(`IndexedDB after Save: ${JSON.stringify(R.steps.idbAfterSave)}`)
  await page.keyboard.press('KeyP'); await sleep(500)
  await sleep(2500)
  R.steps.idbBeforeReload = await idbKeys()
  await page.reload({ waitUntil: 'domcontentloaded' })
  await page.waitForSelector('canvas', { timeout: 120000 })
  let again = null; const rl = Date.now(); const base2 = await jpegSize()
  for (let i = 0; i < 120 && again === null; i++) { const sz = await jpegSize(); if (i > 2 && sz > Math.max(base2 * 2.2, 25000)) again = (Date.now() - rl) / 1000; else await sleep(1500) }
  R.steps.reloadToGameS = again === null ? null : +again.toFixed(2)
  R.steps.idbAfterReload = await idbKeys()
  await page.mouse.click(640, 360); await sleep(800); await page.keyboard.press('Enter'); await sleep(1500)
  await page.keyboard.press('KeyP'); await sleep(900); await shot('9-pause-menu-after-reload')
  await page.keyboard.press('ArrowDown'); await page.keyboard.press('ArrowDown'); await sleep(250)  // Load
  await page.keyboard.press('Enter'); await sleep(4000); await shot('10-after-load')

  // --- 6. resize, visibility ---------------------------------------------------------------
  const size = () => ev(() => { const c = document.querySelector('canvas'); return [c.width, c.height, innerWidth, innerHeight] })
  R.steps.canvas1280x720 = await size()
  await page.setViewportSize({ width: 960, height: 540 }); await sleep(1500)
  R.steps.canvas960x540 = await size(); await shot('11-resized-960x540')
  await page.setViewportSize({ width: 1280, height: 720 }); await sleep(800)
  const p2 = await ctx.newPage(); await p2.goto('about:blank'); await p2.bringToFront(); await sleep(1500)
  R.steps.visibilityOfGamePageWhileOtherTabFront = await ev(() => document.visibilityState)
  await p2.close(); await page.bringToFront()
  R.steps.fullscreen = await ev(async () => { try { await document.documentElement.requestFullscreen(); const ok = !!document.fullscreenElement; await document.exitFullscreen?.(); return ok ? 'works' : 'no element' } catch (e) { return 'rejected: ' + e.message } })
}
await sleep(500)
const long = await ev(() => window.__long)
R.longTasks = { count: long.length, totalMs: long.reduce((a, t) => a + t[1], 0), maxMs: Math.max(0, ...long.map((t) => t[1])), over1s: long.filter((t) => t[1] > 1000), first10: long.slice(0, 10) }
R.steps.chromeBaselineBlankMB = baselineMB
R.transferredMBTotal = +(bytes / 1048576).toFixed(2)
R.headers = headers
R.consoleMessages = consoleMsgs.slice(0, 40)
R.pageErrors = pageErrors.slice(0, 20)
R.failedRequests = failed.slice(0, 20)
R.badResponses = bad.slice(0, 20)
R.totalElapsedS = +since()
writeFileSync(join(OUT, `result-${LABEL}.json`), JSON.stringify(R, null, 2))
console.log('RESULT ' + JSON.stringify({ label: LABEL, renderer: R.webglRenderer, load: R.steps.gameVisibleS, fpsIdle: R.steps.fpsIdle, fpsActive: R.steps.fpsActive, MB: R.transferredMBTotal, errors: consoleMsgs.length + pageErrors.length, bad: bad.length }))
await browser.close()
