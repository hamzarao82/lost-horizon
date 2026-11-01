# Stutter: findings and fixes

Measured with `tests/stutter_bench.gd` (windowed, vsync off, Intel UHD 620, 1280x720). A "spike" is a
frame over 25 ms. Machine noise matters: other Godot processes running at the same time inflate every
number, so the table uses the quiet runs and says so.

Run it: `godot --path . -s tests/stutter_bench.gd` (cold) or `... -- warm` (runs `Warmup.steps()` first).

## What was wrong

| # | Source | Evidence | Fix |
|---|---|---|---|
| 1 | Hit-stop froze the game | `time_scale = 0.05` for 0.05-0.10 s, and a swing that hits four enemies on consecutive frames chained the freezes: longest continuous slow-motion 106-149 ms (game effectively stopped) | `HitStop` redesign: scale 0.3, durations x0.6 and clamped to 0.07 s, never additive, 110 ms cooldown, Off / Light / Normal in Settings. Longest stretch now 76-90 ms and it is slow-motion, not a freeze |
| 2 | First-use render costs | First frame of the arena 435-1200 ms; first heavy fight spikes up to 169-191 ms; first pickup 37-53 ms; first Warden slam 60 ms | `Warmup` draws every material type, the particle quads, the damage-number glyphs, the ring sprite, enemy-label text and the shockwave mesh once in a private SubViewport, plus a silent play of every sound |
| 3 | First-use disk loads | Cold spawn of Heavy 3.4-3.8 ms, Warden 5 ms, first Pickup 4-6 ms; warm 0.5-2 ms | `Warmup` preloads every attack, item, loot table, enemy scene and the pickup scene and keeps references (the engine cache frees unreferenced resources) |
| 4 | Per-slam allocation | Each Warden shockwave built a mesh and a material | Shared static mesh/material (`Warden.ring_resources()`) |
| 5 | Label re-shaping | `Label3D.text = ...` on every health change | Enemy health label only rebuilds when the 10-segment bar moves |

Checked and ruled out (micro-measured, no change needed): every `Fx` call costs under 0.2 ms
(`number` 0.02, `spark` 0.1, `death_burst` 0.18); setting `Label3D.text` costs 0.05 ms (shaping happens at
first draw, which `Warmup` pre-pays); steady-state enemy spawn is 1-3 ms and pickup spawn 0.5-2 ms.
The earlier 13-46 ms "spawn" readings in the bench were first-call loads plus machine contention.

## Results (quiet machine, worst frame / spikes over 25 ms)

| Scenario | Before | After, cold | After, warm-up first |
|---|---|---|---|
| First frames of the arena | 435 ms, 8 spikes | 112-122 ms, 5-6 spikes | 11-25 ms, 0-1 spikes (the cost moves into ~27 loading frames, up to 0.45 s each) |
| First heavy fight (4 enemies) | 169 ms, 8 spikes, 1% low 11 fps | 66-103 ms, 2-5 spikes | 26-44 ms, 1-2 spikes, 1% low 45-62 fps |
| Later heavy fights | 43 ms, 3 spikes | 23-29 ms, 0-1 spike | 20-30 ms, 0-1 spike |
| Longest hit-stop stretch | 106-149 ms at 5% speed | 76-84 ms at 30% speed | 78-90 ms at 30% speed |
| Pickups | 53 ms, 7 spikes | 28-29 ms, 3 spikes | 28-33 ms, 1-2 spikes |
| Wave spawn | 79 ms | 34-40 ms | 27-50 ms, 1 spike |
| Boss slam / shockwave | 66 ms, 3 spikes | 39-47 ms, 2 spikes | 22-24 ms, 0 spikes |

## For the Boot / loading screen

```gdscript
var steps := Warmup.steps()
for i in steps.size():
    steps[i].call()
    progress.value = float(i + 1) / steps.size()
    await get_tree().process_frame
```

Each step does under 10 ms of CPU work, but a few frames are slow because they draw something for the
first time (up to ~0.45 s on this GPU), so the progress bar must not assume even frame times. The first
frames render the arena itself, so run the warm-up after `Main` is in the tree (behind the loading
overlay), not before. Nothing requires the warm-up: without it, the first hit/pickup/slam pays its cost then.

## Still open (outside this agent's files)

- `WaveManager._warm_up()` calls `load()` and drops the result, so the engine frees those resources again.
  Replace it with `Warmup`'s preload (which keeps references).
- A wave spawns 3-4 enemies in one frame (one 27-50 ms frame); stagger them, e.g. one per 0.1 s.
- Pickup collection frames of 28-33 ms come from equipping (weapon model swap) and HUD text updates.
- The pause menu has no hit-stop option yet: `Settings.set_hit_stop(HitStop.Level.OFF / LIGHT / NORMAL)`.
