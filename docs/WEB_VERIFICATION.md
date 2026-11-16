# Web build verification (headless, 2026-11-16)

Build: `Godot 4.7.2` web release export of the `m64` worktree at HEAD `410645e` (after merging master), packaged with `tools/package_web.ps1` and served from `127.0.0.1:8099` by `tools/serve_web.ps1`. Browser: pinned Chromium via browser-automation (headless).

## Sizes (packaged folder, 48.5 MB)

| File | Bytes | MiB |
|---|---|---|
| `index-64f35eda.wasm` (`application/wasm`) | 39,514,754 | 37.7 |
| `index-64f35eda.pck` (`application/octet-stream`) | 10,978,552 | 10.5 |
| `index-64f35eda.js` | 279,815 | 0.3 |

## Timing and console

- Loader visible immediately. The main menu appeared at about 7.6 s in one run, but with New Game and Continue greyed out and the on-screen text "Loading world... 42%" (`docs/screenshots/web_menu_loading_42pct.png`).
- New Game and Arena Mode became enabled sometime before the 60 s sample. The 30 s sample was not checked, so the exact unlock time is not pinned down. Stable live menu: `docs/screenshots/web_menu.png` (60 s).
- Page load time varied between runs (1.4 s, 21.7 s, 91 s for the `load` event), so these numbers are noisy.
- Console errors and warnings: 0 in all five runs.
- Failed requests: 0 in four runs. One run reported `net::ERR_ABORTED` on `index-64f35eda.wasm`. It did not recur in the next three runs, so the cause is unknown.
- Frame rate on the menu under headless rendering: about 15 fps (rAF count over 3 s). This is a software/headless figure and says nothing about real hardware.

## New Game (first 20 s)

- Clicking New Game (canvas coordinates) changed the DOM text to "Starting engine...". A loading overlay with "Ready 100%" and a dimmed 3D preview followed (`web_opening_13s.png`, `web_opening_20s.png`).
- The overlay was still dimmed at about 60 s (`web_opening_60s_skip.png`). The cinematic itself was never visible in these frames.
- A **Skip** button sits in the bottom-right corner, **clipped at the right edge of the 1280x720 viewport** (its label is cut off). This looks like a layout bug, but the frame was mid-fade, so it needs a check on a live viewport before it is filed.
- Not done: pressing Skip, and any input after the overlay.

## Save persistence

Not tested. The pause menu was not reachable: Escape did not open it while the overlay was up. The menu shows "Continue (no save)", so there is no save to reload. Save and Continue need a real playthrough, which headless could not reach.

## Not verifiable here

- **Audio**: no sound check. Headless Chromium here does not play through to a device.
- **Hardware WebGL**: rendering ran on the headless software path, so frame rate, shader cost and GPU memory on a real browser are unknown.
- **Stale build label**: the menu prints "build 8ae890f | 2026-11-14 21:06", a hardcoded constant in `scripts/core/build_info.gd`. It does not match HEAD `410645e`. Update it before any build is shown as current.

## Screenshots

- `docs/screenshots/web_menu_loading_42pct.png`: menu shown while the world still loads (buttons disabled)
- `docs/screenshots/web_menu.png`: menu enabled (60 s)
- `docs/screenshots/web_opening_13s.png`, `docs/screenshots/web_opening_20s.png`: New Game loader overlay
- `docs/screenshots/web_opening_60s_skip.png`: overlay after 60 s, Skip clipped at bottom-right
