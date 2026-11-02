
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
