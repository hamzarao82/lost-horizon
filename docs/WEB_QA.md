
## Update: web load time fix (2026-11-02)

Measured with `tools/webqa/boot_probe.mjs` in headless Chromium 156 on an Intel UHD 620 (real GPU via ANGLE/D3D11, fresh browser profile each run, so no shader cache).

| Build | Engine start | Loading and building | Graphics preparation | Playable | Main thread blocked | Worst stall |
|---|---:|---:|---:|---:|---:|---:|
| Deployed before (QA agent, 4 runs) | n/a | n/a | n/a | 63–92 s | 30–49 s | 2–16 s |
| Sliced reveal only | 11.4 s | 2 s | 56 s | 80.6 s, 80.9 s, 79.3 s | 78 s | 19 s |
| **Sliced reveal + vertex shading on web** | 4.4 s | 2 s | 17 s | **27 s** (twice) | 25 s | 6 s |

Root cause: on this GPU the browser compiles each shader program synchronously the first time it is used, about 1.5 s per decor piece (roughly 56 s in total). Slicing the reveal only moves that cost behind the loading screen. The effective fix is to simplify the shaders for web: `rendering/shading/overrides/force_vertex_shading.web=true` and `force_lambert_over_burley.web=true` in `project.godot` (web feature tag only; desktop and Android keep per-pixel shading). Lighting in the browser is per-vertex; shadows are unchanged. A screenshot of the web build looked correct.

Also fixed: the first click after the intro now captures the mouse (`document.pointerLockElement` is set on click 1, 2 and 3; before, click 1 did nothing). The first-click swing guard still applies.

Cache busting: `tools/package_web.ps1` renames the exported files to `index-<hash>.*` and patches `index.html`, so a redeploy can never pair a new wasm with an old pck. Verified: the packaged build boots in 27 s with no console errors.

Still open: a fresh-profile first load is about 27 s on this laptop; Chromium keeps a shader cache, so repeat visits should be faster (not measured). Phones were not measured. The 38 MB wasm module itself compiles in well under a second here.

## Web boot-time investigation (2026-11-07)
Method: temporary worktrees per commit, web export, `tools/webqa/serve.mjs` plus `tools/webqa/boot_probe.mjs` (desktop Chromium, headless), `reveal_done` on the game clock, two runs each. Other work shared the machine, so run-to-run noise is about ±3 s; a conclusion needs a gap larger than that.

| Build | reveal_done run 1 / run 2 | Reveal pieces |
|---|---|---:|
| Milestone 4 (`c73ef74`) | 26.7 s / 27.1 s | 121 |
| audio, gamepad, military record (`a0fb422`) | 29.8 s / 33.9 s | 122 |
| plus warm-up of character models (`ea4f610`) | 22.0 s / not measured | 122 |
| plus interior dressing (`97a36d0`) | 36.4 s / 36.5 s | 134 |
| visual pass and Milestone 6 (`08d79a3`) | 39.6 s / 41.4 s | 235 |
| current master incl. regions (`69540b2`) | 34.9 s / 31.6 s | 235 |
| same, vegetation scatter skipped on web | 31.8 s / 37.7 s | 136 |

**Findings.**
- Load (`load_done`) stays at 5.5 to 7 s in every build; the growth is in the reveal phase.
- Skipping the vegetation scatter removed 99 reveal pieces and changed nothing outside the noise, so the piece count is not the driver, and the change was reverted (web visuals unchanged).
- The step from `ea4f610` to `97a36d0` (interior dressing, about +14 s on one low run) is the largest single jump seen, but the dressing diff adds only two emissive materials and 12 pieces, which does not explain it; the gap may be partly noise because the `ea4f610` second run was lost.
- The bare reveal phase takes 20 to 29 s whatever the piece count, which suggests the headless Chromium rendering path, not the project's content, dominates it.

**Result.** Not reached: the best current-master runs are 31.6 s and 34.9 s against the 30 s budget. No fix produced a measurable gain, so none was kept. A trustworthy attribution needs a quiet machine and at least five runs per build, or a real GPU browser run.
