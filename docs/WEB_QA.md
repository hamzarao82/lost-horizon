# Web QA (real browser)

Date: 2026-11-02. Tested the **currently deployed** site, https://hamzarao82.github.io/lost-horizon/play/ (the build with the 9.9 MB `.pck`; the lead has since reduced it to 0.49 MB and will redeploy), and a local copy of `site-assets/play`.

## Method
- Browser: Chromium 156 (patchright 1.64.2, revision 1248, user-level install), headless, Windows, Intel UHD 620 (i7-8650U).
- Runner: `tools/webqa/run.mjs` (+ `serve.mjs`, a dependency-free static server). Example:
  `node tools/webqa/run.mjs --url <url> --profile desktop|mobile --mode swift|soft --label <name>`.
  `swift` (the default) ended up using the **real GPU** (ANGLE Direct3D11, Intel UHD 620); `soft` forces SwiftShader (software WebGL).
- Desktop profile: 1280x720, real key and mouse events. Mobile profile: 800x360, touch emulation, Android user agent (the game checks it to show touch controls), touch events through CDP.
- FPS = page `requestAnimationFrame` count (Godot paces itself on it). Long tasks = `PerformanceObserver('longtask')` (main-thread stalls over 50 ms). Memory = working set of all Chromium processes (PowerShell), minus a blank-browser baseline.
- Screenshots and JSON results are in the scratchpad (`...\scratchpad\webqa`), not in the repo.

## Results (deployed site, desktop, real GPU)
| Metric | Result |
|---|---|
| Canvas visible | 0.9 s |
| **Time to playable** (beach scene on screen) | **63-92 s** over 4 runs (local copy: 69.7 s, so not a network/GitHub effect) |
| Main-thread blocking during boot | 13-18 long tasks, **30-49 s in total, worst single task 2.1-15.8 s**. Godot's loading bar and the page are frozen during those. |
| Reload to playable (warm cache) | 30-74 s |
| First-load transfer | **12.0 MB**: `index.wasm` 10.0 MB gzip (38.6 MB decoded), `index.pck` 2.2 MB gzip (10.1 MB decoded), `index.js` 68 KB, html 2 KB |
| FPS | **60 idle, 60 active** (walking, sprinting, jumping, attacking; capped by vsync, so this is "no drops", not headroom) |
| Memory | Chromium working set 1150-1190 MB vs 490-500 MB for a blank browser, so about **680 MB for the game**; JS heap 36 MB (wasm memory is not in the JS heap) |
| Console errors / page errors / failed requests / 4xx | **0 / 0 / 0 / 0** in every run |
| Hosting headers | `application/wasm`, **gzip on wasm, js, pck and html**, `Cache-Control: max-age=600` |
| Forced software WebGL (SwiftShader) | 1.3 FPS, 82 s to playable. This is a pessimistic floor for a machine with no GPU acceleration, not a prediction for a phone. |

## Mobile profile (800x360, touch, Android UA)
- Touch UI appears: Tele, Spin, Heal, Heavy, Dodge, Lock, Atk, Jump, and the pause button at top-left (screenshot `deployed-mobile-4-beach-start.png`).
- Held the stick, then tapped all eight buttons (`deployed-mobile-6-after-button-taps.png`): the view/player moved, the **stamina bar drained** (attack/jump taps registered), and the label changed to **`Teleport 1/2 next in 10:00`** (the Tele tap used a charge).
- 60 FPS idle and active on this GPU; time to playable about 68 s; 43.7 s of long tasks (worst 10.6 s); 0 errors.
- Not testable here: real phone GPU/thermal behaviour, memory limits, browser UI chrome, multitouch (the test used one finger at a time).

## Web-specific checks
| Check | Result |
|---|---|
| First click must not swing the weapon | **Pass.** Screenshot 120 ms after the first click shows an idle character and full stamina. Matches the code (`Player._attacks_allowed()` blocks attacks while the mouse is not captured). |
| Pointer lock on first click | **Fail (UX bug, see Bug 2).** After the first click `pointerLockElement` is null and no `pointerlockchange` fired; after the **second** click it is `CANVAS#canvas` (one event, no `pointerlockerror`). |
| Save and persistence | **Pass.** P opens the pause menu (shows "Load (no save)"), Save wrote `/userfs/godot/app_userdata/Lost Horizon/save_slot_1.json` and `teleport.cfg` to IndexedDB; after a page reload both files were still there, the menu showed "Load" (enabled), and the teleport recharge timer kept counting (09:59 -> 08:37 across the reload). Load restored the beach scene. |
| Pause menu (P) | Works; focus navigation with Down/Enter works. |
| Resize | Pass: canvas follows the window (1280x720 -> 960x540 -> back). |
| Fullscreen | `requestFullscreen()` succeeded. |
| Keys E, R, Ctrl, C, T, Q, Space, Shift | No errors; T used a teleport charge (HUD 2/2 -> 1/2). Combat keys (LMB/RMB) drained stamina in the screenshot. |
| Audio | AudioContext state was `running` after the first click (with and without the autoplay-policy flag). I could not capture the state *before* any gesture and cannot hear output, so "audio plays after a gesture" is **not verified**. |
| Background tab | **Not testable**: headless Chromium reports `visibilityState = "visible"` for the game page even with another tab in front. |

## Bugs found (ranked)
1. **Time to playable is 60-90 s with the main thread blocked for 30-49 s** (worst single stalls 2-16 s, starting about 11 s in). Likely sources are the 38 MB wasm compile, engine start, and the Boot scene's loading and warm-up steps running synchronously in the single-threaded web build. The Boot screen's progress bar cannot animate during a stall, so the page looks frozen. Repro: open the deployed URL in any Chromium; `tools/webqa/run.mjs` prints the long tasks. Mitigations to try: confirm what the long tasks are (Chrome performance trace), split warm-up steps further or skip heavy ones on web, check that the wasm is compiled with streaming, and consider `variant/extensions_support` off (already). Not verified on a real phone, where it will likely be slower.
2. **The first click does not capture the mouse.** Repro: load the page, let the opening play, click once (this skips the intro), move the mouse: the camera does not turn. A second click captures the pointer. Cause (from reading the code, not proven): the intro pauses the tree, so the camera's `_unhandled_input` capture handler does not run for the skipping click. Suggest capturing on the first mouse button press after the intro ends, or showing "Click to play".
3. **Memory is high for a web target**: about 680 MB above a blank browser (about 1.15 GB total working set). The earlier budget was under 1 GB in the tab. Low-RAM phones may kill the tab. Not measured on a device.
4. **`Cache-Control: max-age=600`** (GitHub Pages default): after a redeploy, returning players can run a stale `index.pck` with a new `index.wasm` for up to 10 minutes, which can break the game. Consider cache-busting, for example a version query on the script and pck URLs in `index.html` (not tried here).
5. The loading splash is the stock Godot logo; it's not a bug but the first thing every player sees for about 45 s. A custom HTML shell would help perceived load.

## Limits of this test
- One machine: an i7-8650U laptop with an Intel UHD 620, not a phone. FPS of 60 is vsync-capped and not a measure of headroom. Other processes (other agents' builds) may have been running during some runs, so load times varied (63-92 s); I did not control for that.
- Headless Chromium: no real window focus, no real visibility changes, no audio output, no real touch hardware.
- Load-time detection uses a screenshot-size heuristic plus long-task data; it is accurate to a few seconds.
- The save test confirms the files persist and the menu state changes; it does not compare the restored player position (the save format has no position by design).
- The software-WebGL run could not complete the save step (menu keypresses are too slow at 1.3 FPS); that is a test artefact, not a game bug.
