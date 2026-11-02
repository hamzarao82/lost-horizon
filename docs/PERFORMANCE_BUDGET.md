# Performance Budget

Tags are explained in [MILESTONE_004.md](MILESTONE_004.md). Targets are **test targets, not guarantees**. The measurement log is `PERFORMANCE.md`; this document sets the budgets and states what has and has not been measured.

## 1. Targets

| Platform | Frame rate target | Status |
|---|---|---|
| Windows | 60 FPS | measured on an integrated-graphics laptop only (see section 2) |
| Android | 30 FPS | **never measured** (no physical device run; an emulator could not start) |
| Web | 30 FPS | measured in desktop Chromium only (60 FPS cap), not on phones |

## 2. Measured baselines `[IMPLEMENTED]` (Intel UHD 620 laptop, 1280x720, scripted four-enemy fight, `tests/benchmark.gd`)

| Build | Avg FPS | 1% low FPS | Draw calls (peak) | Notes |
|---|---:|---:|---:|---|
| `master` (v0.1.0 code) | 93–99 (earlier quiet run: 142) | 47–49 | 177–181 | box characters |
| `milestone-002` | 91 | 39–40 | 111 | skinned characters, kit environment, effects |
| `milestone-003` | 96–97.5 | 38–41 | 150–156 | areas C and D, dressing, patrols |

Other recorded numbers: web export wasm 37.7 MB (about 10 MB gzipped), pack 0.57 MB, Windows exe 104 MB plus a 0.57 MB pack, Android debug APK 27.5 MB; web time to playable about 27–30 s on the same laptop with the real GPU (was about 80 s before the shading fix), Chromium memory about 1.0 GB, first load transfer about 12 MB; Windows frame spikes in the first heavy fight 26–44 ms after warm-up. Machine load changes these numbers by up to 10–15%: only quiet-machine runs are compared.

## 3. Budgets for the vertical slice (`[NEW-M4]`)

| Category | Windows | Android | Web | Measured by |
|---|---|---|---|---|
| Frame rate | ≥ 60 | ≥ 30 | ≥ 30 | benchmark, F3 overlay |
| Frame spike | none over 40 ms in a heavy fight | none over 70 ms | none over 70 ms | `stutter_bench` |
| Draw calls (peak, 4 enemies) | ≤ 250 | ≤ 200 | ≤ 200 | overlay/benchmark |
| Triangles on screen | ≤ 300k | ≤ 150k | ≤ 150k | overlay |
| Characters | player ≤ 8k tris, enemy ≤ 6k, boss ≤ 12k; current art is 1.8–2.5k each | same | same | `verify_glb` |
| Animated characters at once | 8 | 6 | 6 | benchmark |
| Active enemies | 6 (waves 4 + patrol 4 never together by design) | 5 | 5 | tests, benchmark |
| Patrollers active | 4 (existing cap) | 4 | 4 | `patrol_check` |
| Textures | 512–1024; the current game uses vertex colours and a few generated textures | same | same | asset review |
| Texture memory | ≤ 150 MB | ≤ 100 MB | ≤ 100 MB | profiler `[UNVERIFIED]` |
| Dynamic lights | 1 sun | 1 sun | 1 sun | scene review |
| Shadows | sun only, distance ≤ 40 m, quality-scalable | off by default (Low) | sun, distance ≤ 30 m | settings |
| Particles | pooled, ≤ 43 simultaneous effects, scale with quality | scale 0.4 | scale 0.4–0.7 | `fx_check` |
| Physics | static colliders only for decor that must block; no new rigid bodies | same | same | `dressing_check` |
| Navigation | direct steering today; baked meshes only if needed, ≤ 4 agents | same | same | review |
| Audio | ≤ 3 MB total, ≤ 12 voices (desktop), 8 (mobile/web) | | | file size, profiler |
| Build size | exe ≤ 150 MB | APK ≤ 80 MB | wasm+pck ≤ 60 MB (≤ 15 MB gzip) | export |
| Web load | n/a | n/a | ≤ 30 s fresh profile, ≤ 12 MB transfer | `boot_probe.mjs` |
| Memory | ≤ 600 MB | ≤ 1.5 GB | ≤ 1.2 GB tab | profiler `[UNVERIFIED]` |

Quality levels: Low (Android and mobile web default), Medium, High (desktop default). The web build already uses simplified shading (`force_vertex_shading.web`).

## 4. Known cost drivers and mitigations
| Driver | Evidence | Mitigation |
|---|---|---|
| Shader compilation on web | 56 s of the old 80 s boot | vertex shading on web, sliced reveal (`master`) |
| Skinned characters | not measured on phones | cap animated characters, one LOD, shared material |
| Decor draw calls | kit merged into 4 draws on `milestone-002` | MultiMesh and merged static meshes |
| First-use hitches | removed by warm-up on desktop; web warm-up is intentionally light | keep warm-up steps under 10 ms each |
| Memory in browsers | about 1 GB | lazy audio, avoid duplicate textures |
| Thermal limits on phones | unknown | 30 FPS cap option, Low quality default |

## 5. Test plan
| Test | Device | Procedure | Record |
|---|---|---|---|
| Desktop benchmark | the dev laptop plus one stronger PC if available | `tests/benchmark.gd` x3 on a quiet machine, then a 10-minute free play | avg/1% FPS, draw calls, memory |
| Stutter bench | desktop | `tests/stutter_bench.gd -- warm` | spikes over 25 ms by scenario |
| Web | desktop Chromium and Firefox, plus a phone browser | `tools/webqa/boot_probe.mjs`; then play 10 minutes; check memory | load time, FPS, memory, console errors |
| Android | physical phone (owner's Redmi K80 planned) | install the APK, enable the FPS toggle in Settings, play the mission | FPS in each area, thermal throttling after 15 minutes, crashes |
| Low-end Android | one older phone if available `[PROPOSED]` | same | pass/fail on 30 FPS at Low |
| Regression | desktop | all suites plus the benchmark after every merge | trend table in `PERFORMANCE.md` |

A budget miss is recorded in `PERFORMANCE.md` with the cause and either fixed or accepted by the owner with a note in the release notes.

## 6. Unverified
Everything about Android; web on phones; the combined cost of merged `milestone-002` + `milestone-003` content (never built together); texture memory and RAM peaks (not profiled).
