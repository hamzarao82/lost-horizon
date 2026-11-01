# Loading

The game used to load in one go: the engine loaded and instanced Main, whose `_ready` built the whole
island, all before the first frame was drawn. The window stayed blank and one frame froze for
over half a second. Startup is now a staged boot behind a progress screen.

## Flow

`project.godot` main scene is `scenes/boot/Boot.tscn` (script `scripts/core/boot.gd`, a CanvasLayer at layer 200 so
Main's HUD, pause menu and touch layers never draw over it).

| Phase | What happens | Per-frame cost |
|---|---|---|
| LOADING | `ResourceLoader.load_threaded_request` for Main and every resource the first minute needs (everything in `resources/attacks, items, loot`, `scenes/enemies, loot`, `assets/audio`). Requests are issued inside an 8 ms budget per frame, so a single-threaded web export (where a request can do real work) spreads them over frames. | polling only |
| WARMING | One step per frame: instance Main, then each step from `res://scripts/core/warmup.gd` (`static func steps() -> Array[Callable]`, optional, run **one per frame** because some steps wait for a rendered frame), then add Main to the tree with `process_mode = DISABLED` so nothing plays behind the screen. | 8 ms budget |
| BUILDING | Waits for `ArenaDecor.is_built()` (stages below). | none |
| WARM_RENDER | One of each enemy and a pickup are spawned in view for 2 frames so their shaders and particles compile behind the opaque screen, then freed. | one frame |
| SETTLING / FADING | 3 presented frames, Main is enabled (`PROCESS_MODE_INHERIT`), 0.35 s fade, Boot frees itself. | none |

`get_tree().current_scene` is set to Main, so `reload_current_scene()` (death restart, pause menu Restart/Load)
restarts Main directly, not the boot screen.

Failure path: any resource that cannot be loaded shows the file name and a **Retry** button; nothing starts.
`failed(message)` is emitted. Retry clears and starts over.

Progress is never allowed to move backwards. Weights: load 50%, warming 15%, decor 27%, warm-render 8%.

## Staged decor (`scripts/world/arena_decor.gd`)

`_build()` is a coroutine that yields one frame between stages, so Main's `_ready` returns immediately:

1. sand texture, 2. rock texture, 3. water+cloud textures, 4. obstacle materials + terrain (the plain floor is hidden only
now, so there is never a frame with no ground), 5. water, 6. palms+rocks, 7. fences+wreck+clutter, 8. outpost,
9. final props mesh, 10. clouds. A rebuild (quality change) supersedes a running build by serial number; freeing the node
mid-build is safe. `is_built()` and `build_finished` report completion; `stage_ms` holds the cost of each stage.

Flags: `ArenaDecor.build_synchronously` builds everything in `_ready` (old behaviour). It is forced under
`--headless` so existing tests stay deterministic. `ArenaDecor.force_staged` overrides that for tests.

`WaveManager._warm_up()` now loads only what is cold, at most one resource per frame (Boot has normally cached all of it).

## Measured (Intel UHD 620, 1280x720, Godot 4.7.2, windowed)

| | Before | After |
|---|---|---|
| Worst frame while loading/building Main | 620-714 ms (frames over 33 ms: 5-7 of 240) | about 150 ms (hidden behind the boot screen) |
| Decor build only, worst frame | 267-293 ms | 56-59 ms (largest stage about 30 ms) |
| Window while loading | blank | title, progress bar, percent, tips |
| Process start to first boot frame | n/a | 3.8-5.3 s (engine + autoloads, see below) |
| Boot first frame to playable | n/a | 3.2-4.2 s |
| Worst frame in the 180 frames after the game starts | 5-7 hitches over 33 ms | 25-31 ms in two of three runs, 140 ms in one cold run |

Boot takes longer overall than the old single freeze (it pays shader compiles and the warm-up steps while the bar
is up), in exchange for a visible, animated screen and no hitch in the first fight or first seconds of play.

Run it yourself:

- real flow: `godot --path . -- --boot-report` (prints phase timings and decor stage costs, then 180 frames of
  post-boot frame times, then quits)
- old flow: `godot --path . -s tests/boot_timing.gd`
- decor only: `godot --path . -s tests/decor_timing.gd`
- logic: `godot --headless --path . -s tests/boot_check.gd` (32 checks)

## Known limits

- The 3.8-5 s before the boot screen draws is the engine (about 2.7-3.7 s on this laptop) plus the autoloads'
  `_ready` (about 1-2 s: `Fx` builds all its pools, `AudioManager` loads 13 sounds). Autoloads run before any scene, so Boot
  cannot hide that; making them lazy is the next win.
- On a single-threaded web export `load_threaded_request` may do the work inside the call. The per-frame request budget
  spreads that out, but Main.tscn itself is one large request. This was not measured in a browser.
- The 8 ms warm-up budget is a target, not a guarantee: a single step (instancing Main, adding Main) can take longer.
