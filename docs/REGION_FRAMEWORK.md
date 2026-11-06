# Region Framework (Milestone 7, phase 1)

Status 2026-11-06. Legend: **Verified** = a test was run and passed; **Not tested** = built but unproven. The Dead Coast, Blackwood and Research Complex regions are **stubs** (a ground slab and a sign): the framework is real, the levels are not.

## What exists
| Piece | File | Status |
|---|---|---|
| `RegionData` resource: id, name, scene, entry points, exits, unlock flag, environment and ambience names, map extents | `scripts/regions/region_data.gd`, `resources/regions/*.tres` | Verified (loads, ids, exit targets valid) |
| `Region` base (enter, capture_state, restore_state) | `scripts/regions/region.gd` | Verified through `StubRegion` |
| `RegionExit` (walk-in trigger, refuses locked regions with a caption) | `scripts/regions/region_exit.gd` | Verified (walking into it travels, both ways) |
| `RegionManager` autoload: travel, unload, entry placement, fade, unlock, per-region state | `scripts/regions/region_manager.gd` | Verified |
| `RegionStore` static helpers: known ids, data cache, save-section sanitising | `scripts/regions/region_store.gd` | Verified (hostile data) |
| `PersistentIds` and `RegionFlags` | `scripts/regions/persistent_ids.gd`, `region_flags.gd` | Verified |
| Stub regions | `scenes/regions/StubRegion.tscn`, `stub_region.gd` | Verified; placeholder content |
| Save version 4 with migration from 3 | `scripts/core/save_manager.gd` | Verified (fixture v3 save) |

## How it works
- **Main stays the container** (player, HUD, menus, sky, sun). Tests and the game still instantiate `Main.tscn` unchanged; the manager recognises a node named `Main` that has an `Outpost17` child and registers it as region `outpost_17`.
- **Leaving Outpost 17:** its nodes (floor, walls, decor, wave manager, world flow, enemies and pickups that were added at runtime) are detached from Main, not freed. They are out of the tree (no physics, rendering or timers) and kept for the return, so enemies, doors and puzzle state are exactly as left. **Trade-off:** Outpost 17's memory stays allocated while the player is away; it is not streamed out. Rebuilding it from code on each return would be slow and would lose state. When Outpost 17 is turned into its own scene this can become a real unload.
- **Other regions** are scenes: loaded with `ResourceLoader.load_threaded_request` on desktop and a plain `load` on web (single-threaded export), instantiated with the position set before `add_child`, and freed when the player leaves. Only one region is in the tree at a time.
- **Unlocking:** a region opens when `RegionManager.unlock(id)` was called or its `unlock_flag` is set in `WorldState` (Dead Coast: `mission_first_signal_complete`; Blackwood: `dead_coast.region_complete`; Research Complex: `blackwood.region_complete`). Flags use the convention `<region_id>.<flag>`; `RegionFlags` is the helper.
- **Exits** come from the region's data, not from the level scenes: the manager creates one `RegionExit` per entry in `exit_points` when a region is loaded and removes them when it is left.
- **Travel call:** `await RegionManager.travel(region_id, entry_id)`; refused (and false) when busy, unknown, locked, or already there. `region_changed(old, new)` fires after the player is placed.
- **Presets:** after arriving the manager calls `AudioManager.set_region_ambience(name)` **if that method exists**. It does not exist yet, so no region ambience changes today. Environment presets (sky, fog, sun) are named in the data but **not applied yet**.

## Saving (version 4)
`regions` section: `{current, unlocked, states: {region_id: {ids: {claimed id: true}, custom: {...}}}, position}` (position only outside Outpost 17). Migration from version 3 puts the player in Outpost 17 with only Outpost 17 unlocked. Everything is sanitised on load: unknown regions dropped, types fixed, positions clamped, claimed ids capped at 500, custom state capped at 20000 characters, and being saved in a region that is not unlocked falls back to Outpost 17. After `load_game`, the next `Main` travels to the saved region and position once the player has finished setting up. Checkpoints record their region, and dying queues a respawn in that region.

## Persistent ids
`PersistentIds.claim(region, id)` returns true once per region and id, saved with the region state, so reloading cannot repeat a reward. Intended for collectibles, caches, cleared encounters and unique rewards in the coming levels.

## Fixes made while building it
- Re-attaching Outpost 17 re-emits `node_added`, which made `AudioManager` and `FxManager` hook enemies, pickups and the wave manager a second time (double sounds, double effects). They now connect once.
- The exit trigger defers the travel call so no physics object is removed inside its own physics callback.

## Tests
`region_check` (59 checks) and `region_save_check` (42 checks). They cover: data, locking and unlocking, travel both ways, the same Outpost nodes coming back, state per region, walking into exits, no leaked nodes over five round trips, saving inside Dead Coast and loading back to the same place and state, v3 fixture migration, hostile data, claims surviving a reload, and checkpoints recording their region.

## Not done
- No real Dead Coast, Blackwood or Research Complex level.
- Environment and ambience presets are named but not applied; `AudioManager.set_region_ambience` is missing.
- Outpost 17 is detached, not unloaded (memory stays).
- No world map screen yet.
- The respawn into another region after death is verified up to the queued restore, not through the real 2 s scene reload.
- Web and Android transitions are not tested; the web path (a plain load) has not been run in a browser.
- Region transitions use a fade only; there is no loading screen text or progress.
