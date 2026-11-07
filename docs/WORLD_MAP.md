# World Map (Milestone 7)

Status 2026-11-06. **Verified** = covered by `tests/map_check.gd` (125 checks) and looked at in a windowed screenshot; **Not tested** = built but unproven.

## What it is
A map screen with two levels, opened from the pause menu (**Map** button) or the **M** key:
1. **Overview:** a stylised island with the four regions (Outpost 17, Dead Coast, Blackwood, Research Complex), joined by the campaign route. Each node shows its status: **current** (gold ring, "You are here"), **available** (blue), **completed** (green tick), **locked** (grey padlock with the reason, e.g. "Complete Dead Coast"). Selecting a node prints its status and unlock hint.
2. **Region view:** a top-down schematic of the region the player is in: explored areas (filled, named), unexplored areas (fog with a "?" and no name), point landmarks that stay hidden until their area is found, exits with their target and lock state, the player (arrow facing the player's heading), the objective compass target, and a legend. Pan and zoom with the toolbar buttons (56 px tall), the mouse wheel and drag, or the right stick; **Center** resets.

## Files
| File | Role |
|---|---|
| `scripts/regions/map_data.gd` (`MapData`) | landmark data, access status, discovery, objective marker, world-to-canvas transform. No drawing. |
| `resources/regions/maps/*.tres` | one `MapData` per region (landmark lists, overview position, unlock hint) |
| `scripts/ui/map_canvas.gd` (`MapCanvas`) | draws both levels with `_draw`; redraws only when told to |
| `scripts/ui/map_screen.gd` (`MapScreen`) | the screen: toolbar, data from `MapData`, discovery listener, pause while open |
| `scripts/ui/pause_menu.gd` | additive: Map button, **M** key, `show_map()` |
| `tests/map_check.gd` | 125 checks |

## Rules
- **Access status** (`MapData.region_status`): the region the player stands in is *current*; otherwise *locked* when `RegionManager.is_unlocked` is false, *completed* when `<region>_region_complete` or `<region>_completed` is set, else *available*. The framework unlocks the next region with `<region>_region_complete`, so a finished region reads as completed.
- **Discovery:** the screen listens to `WorldState.area_entered` for as long as the pause menu exists (open or not) and sets `<region>_discovered_<area_id>` for the current region. A landmark with an empty `flag` is always known (the arrival area); one with a flag is fog until it is set. Point landmarks (checkpoint) are hidden entirely until found.
- **Flag names use underscores and stay at 48 characters or less.** `WorldState.from_dict` keeps only `[a-z0-9_]` ids up to 48 characters, so a dotted or longer flag silently vanishes on load. `map_check` round-trips every flag the map can set through a real `WorldState.to_dict()` / `from_dict()` and checks the length.
- **Objective marker:** the objective compass node's target, shown only on the map of the region the player is in and only when it lies inside that region's extents (`MapData.objective_marker`). It is the same target the compass arrow uses; there is no separate "mission destination" marker.
- **No per-frame work:** the canvas redraws on open, on a `WorldState.flag_changed`, `RegionManager.region_changed` or `QuestManager.tracker_changed` signal, and on pan or zoom. `map_check` counts `draw` signals: none in 30 idle frames, one or more after a data change.
- The screen pauses the tree while open and restores the previous state on close (same base as the other RPG screens).

## Data status
| Region | Landmarks | Status |
|---|---|---|
| Outpost 17 | 6: the four real areas copied from `Outpost17.AREAS` (a test fails if they drift), the beach checkpoint and the Warden's Arena | real positions |
| Dead Coast, Blackwood, Research Complex | 7, 7 and 6 areas with the names from the milestone plan | **PROVISIONAL** placeholder rectangles. Replace the rects in `resources/regions/maps/*.tres` with the real level positions when the builders land; only the area ids must match the ids those levels emit through `WorldState.area_entered`. |

## Tests (`tests/map_check.gd`, 125 checks, 0 failed)
Resource sanity (ids unique, rects inside the region extents, Outpost 17 matches the level, malformed entries skipped); the four statuses and the unlock hints; discovery (fog and hidden names, per-region flags, real `WorldState` round trip of every map flag, flag length); objective marker rules; the transform (centre, aspect ratio, north up, zoom, pan); the screen (player marker and facing, objective marker, discovery through the real signal, opens paused on the current region, overview and detail data, locked-region message, zoom and pan limits, redraw only on demand, M closes it); layout at 1280x720, 1600x720 and 800x360 in both levels (panel fits, buttons at least 56 px, toolbar buttons do not overlap, canvas at least 300x150, toolbar and canvas do not overlap); the pause menu has a Map button and **M** opens it in a real `Main` scene.

## Screenshots (windowed, 1280x720, real Main scene)
Looked at after fixes: the region view (explored areas named, fog with "?", objective and player markers, locked exit label), the mixed overview (completed, current, available and locked nodes), and the all-locked overview with a selected locked region. Defects found and fixed from the first pass: the objective label covered the area name; the exit label sat under the legend strip; the unlock hint was cut off; route lines ran through the labels.

## Known limits
- Dead Coast, Blackwood and Research Complex maps are placeholders; their region view cannot be judged until the real levels exist.
- The region view of Outpost 17 is tall and narrow, so much of a wide screen is empty; no minimap is drawn during play.
- Not tested: touch dragging and pinch zoom on a device, gamepad right-stick panning with a real pad (the code reads the stick axes; only the code path without a pad ran), Android and web.
- At 800x360 the toolbar wraps to a second row and the canvas is the remaining height (the test enforces at least 150 px tall).
- The F3 stats overlay draws over the screen title in debug windows (affects every full-screen RPG screen, not only this one).
- Discoveries are ordinary `WorldState` flags, which the save already stores; the round trip is tested at the `WorldState` level (`to_dict` / `from_dict`), not through a complete save file written and loaded by `SaveManager`. A save made before this change simply has nothing discovered except the arrival areas.
