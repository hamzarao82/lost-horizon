# Performance log

Budgets: Windows 60 FPS; web and Android 30 FPS; web under 50 MB build and ~1 GB RAM; textures 512 (1024 hero only); 4 active enemies.
Dev machine: i7-8650U, Intel UHD 620, 15.9 GB. Android test device: Redmi K80.
Overlay: F3 toggles (on by default in debug builds).

| Date | Build | Platform | Scene | Avg FPS | Draw calls | Mem MB | Size MB | Notes |
|---|---|---|---|---|---|---|---|---|
| 2026-11-01 | Godot 4.7.2 | Web export (no threads) | Test arena | not measured | n/a | n/a | 39 MB wasm (~10 MB gzip) + 71 KB pck | Export works; not yet run in a browser |
| 2026-11-01 | Godot 4.7.2 | Windows export | Test arena | not measured | n/a | n/a | 105 MB | Export works |
| 2026-11-01 | Godot 4.7.2 + audio/rig/boss/menu | Windows (editor run) | 4 enemies, auto-attacking, vsync off | 103 avg (1% low 52) | 167 peak | 41 | 105 MB | Intel UHD 620, 1280x720, tests/benchmark.gd |
| 2026-11-01 | same | Web export | n/a | not measured | n/a | n/a | 39 MB wasm + 0.35 MB pck | no browser measurement yet |
| 2026-11-01 | same | Android debug APK | n/a | not measured | n/a | n/a | 28.6 MB | built, signed with debug key; not run on a device |
| 2026-11-01 | + lock-on, save, fx, island decor | Windows (editor run) | 4 enemies, auto-attacking, vsync off | 142 avg (1% low 71-75) | 173-178 peak | 48 | 109 MB | Intel UHD 620, 1280x720 |
| 2026-11-01 | same | Web export | n/a | not measured | n/a | n/a | 39 MB wasm + 0.43 MB pck | exported, not run in a browser by me |
| 2026-11-01 | same | Android debug APK | n/a | not measured | n/a | n/a | 28.7 MB | exported, not run on a device |

## Stutter investigation (2026-11-02)
Details in docs/STUTTER.md. Benchmark: `godot --path . -s tests/stutter_bench.gd [-- warm]` (Intel UHD 620, vsync off).
- Hit-stop was the main "lag": 5% game speed for 0.05-0.10 s, chained across enemies (up to 149 ms). Now 30% speed, <= 0.07 s, no chaining.
- First-use costs (shader compile, glyph rasterizing, disk loads) caused the 60-435 ms spikes; `Warmup.steps()` moves them behind the loading screen. Worst frame in the first heavy fight: 169 ms -> 26-44 ms.
- Fx calls, Label3D text assignment, and steady-state spawns were measured and are cheap (< 0.2 ms, 0.05 ms, 1-3 ms).
| 2026-11-02 | Milestone 1 | Android debug APK (arm64) | static analysis only | not measured | n/a | not measured | 29.4 MiB (libgodot 72 MiB unpacked) | NOT RUN: no phone attached; emulator refused to boot (needs 7.4 GB free, C: has 3.1 GB). See docs/ANDROID_QA.md. Export also packs about 9 MB of website/test files (node_modules) |
| 2026-11-02 | Milestone 1 | Android (Redmi K80) | n/a | pending | pending | pending | n/a | awaiting the owner's device test; run tools/androidqa/device_test.ps1 |
