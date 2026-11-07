# World Map (Milestone 7)

Status 2026-11-07. **Verified** = covered by `tests/map_check.gd` (160 checks) and, for how it looks, a windowed screenshot that was looked at. **Not tested** = built but unproven.

## What it is
A map screen with two levels, opened from the pause menu (**Map** button) or the **M** key:
1. **Overview:** a stylised island with the four regions (Outpost 17, Dead Coast, Blackwood, Research Complex), joined by the campaign route. Each node shows its status: **current** (gold ring, "You are here"), **available** (blue), **completed** (green tick), **locked** (grey padlock with the reason, e.g. "Finish Dead Coast: Lost Cargo"). Selecting a node prints its status and unlock hint.
2. **Region view:** a top-down schematic of the region the player is in: explored areas (filled, named), unexplored areas (fog with a "?" and no name), point landmarks that stay hidden until their area is found, exits with their target and lock state, the player (arrow facing the player's heading), the objective compass target, and a legend. Pan and zoom with the toolbar buttons (56 px tall), the mouse wheel and drag, or the right stick; **Center** resets.

## Files
| File | Role |
|---|---|
| `scripts/regions/map_data.gd` (`MapData`) | landmark data, access status, completion, discovery flags, objective marker, world-to-canvas transform. No drawing. |
| `resources/regions/maps/*.tres` | one `MapData` per region (landmarks, exits, overview position, unlock hint) |
| `tools/gen_map_data.gd` | writes the Dead Coast and Blackwood map files from the builders' own area tables |
| `scripts/ui/map_canvas.gd` (`MapCanvas`) | draws both levels with `_draw`; redraws only when told to |
| `scripts/ui/map_screen.gd` (`MapScreen`) | the screen: toolbar, data from `MapData`, discovery listener, pause while open |
| `scripts/ui/pause_menu.gd` | additive: Map button, **M** key, `show_map()` |
| `resources/regions/dead_coast.tres`, `blackwood.tres` | only the `map_extents` line changed, to the real level bounds |
| `tests/map_check.gd` | 160 checks |

## Rules
- **Access status** (`MapData.region_status`): the region the player stands in is *current*; otherwise *locked* when `RegionManager.is_unlocked` is false, *completed* when a completion flag is set, else *available*. Unlocking is the campaign's job (`CampaignFlow` sets `<region>_unlocked`); the map only reads it.
- **Completion comes from the campaign chain** (`CampaignFlow.CHAIN`): a region is completed when the flags that unlock the NEXT region are set (its `after` flag or any alias): Outpost 17 `mission_first_signal_complete`; Dead Coast `dead_coast_mission_3_complete`, `dead_coast_region_complete` or `dead_coast_cargo_complete`; Blackwood `blackwood_mission_3_complete`, `blackwood_region_complete` or `blackwood_research_complex_access`; the Research Complex (no next region) `research_complex_mission_4_complete`. `<region>_region_complete` and `<region>_completed` always count. So the map and the campaign cannot disagree.
- **Discovery:** the screen listens to `WorldState.area_entered` for as long as the pause menu exists (open or not) and sets `<region>_discovered_<area slug>` for the current region (`RegionFlags.key`). The slug is the area id with a leading `<region>_` removed, so `blackwood_research_perimeter` gives `blackwood_discovered_research_perimeter` (39 characters) instead of an unsaveable 49. A flag that would still exceed 48 characters is refused with a warning. A landmark with an empty `flag` is always known (the arrival area); one with a flag is fog until it is set. Point landmarks (the beach checkpoint) stay hidden until found.
- **Flag names use underscores only and at most 48 characters.** `WorldState` keeps only `[a-z0-9_]` ids up to 48 characters when loading, so a dotted or longer flag silently vanishes on load.
- **Objective marker:** the objective compass node's target, shown only on the map of the region the player is in and only when it lies inside that region's extents (`MapData.objective_marker`). It is the same target the compass arrow uses; there is no separate "mission destination" marker.
- **Exits:** Outpost 17 draws the exits of its `RegionData`. Dead Coast and Blackwood carry their own exit list in the map file (the real builder positions), because their `RegionData.exit_points` still describe the stub regions (exits at z = ±36). Locked state is `not RegionManager.is_unlocked(target)`.
- **No per-frame work:** the canvas redraws on open, on a `WorldState.flag_changed`, `RegionManager.region_changed` or `QuestManager.tracker_changed` signal, and on pan or zoom. `map_check` counts `draw` signals: none in 30 idle frames, one or more after a data change.
- The screen pauses the tree while open and restores the previous state on close (same base as the other RPG screens).

## Data status
| Region | Landmarks | Status |
|---|---|---|
| Outpost 17 | 6: the four real areas from `Outpost17.AREAS`, the beach checkpoint and the Warden's Arena | real positions; a test fails if the areas drift |
| Dead Coast | 7 areas from `DeadCoast.AREAS` (ids `dc_*`) with their real rectangles (a 245 m long strip along the shore), 2 exits | **real**, generated; a test fails if it drifts from the builder |
| Blackwood | 7 areas from `Blackwood.AREAS` (ids `blackwood_*`), 2 exits, extents = `Blackwood.BOUNDS` | **real**, generated; a test fails if it drifts |
| Research Complex | 6 areas from the milestone plan | **PROVISIONAL**: that level does not exist yet; replace the rects when it does |

If a builder's area table changes, run `godot --headless --path . -s tools/gen_map_data.gd` and apply the extents it prints to the region's `RegionData.map_extents`; `map_check` fails until you do.

## Tests (`tests/map_check.gd`, 160 checks, 0 failed)
Resource sanity (ids unique, rects inside the extents, Outpost 17 matches the level, malformed entries skipped); the four statuses and unlock hints; completion from the campaign flags including every alias and the last region; discovery (fog and hidden names, per-region flags, flag length); the real levels (map equals the builders' rects, names and ids, extents hold every area and exit, every builder id gives a flag within 48 characters, an over-long id is refused); markers and the transform; the screens (player marker and facing, objective marker, discovery through the real signal, Dead Coast region view with its real exits, lock state following unlocks, zoom and pan limits, redraw only on demand, M closes it); **a real `SaveManager.save_game` / `load_game` round trip** (an Outpost 17, a Dead Coast and the long Blackwood discovery, and a completion flag, all through a real save file in the per-process test slot); a real `WorldState.to_dict()` / `from_dict()` round trip of every flag the map can set; layout at 1280x720, 1600x720 and 800x360 in both levels; and the pause menu Map button and the M key in a real `Main` scene.

**The dotted-flag bug is guarded.** As an experiment the discovery flag was temporarily changed to the dotted form `<region>.discovered.<id>`: `map_check` then failed 12 checks, including the real save and load ones (and the round trip listed every lost flag). The code was restored afterwards.

## Screenshots (windowed, 1280x720, real Main scene)
Looked at: the Outpost 17 region view (explored areas named, fog with "?", objective label beside its marker, the player arrow, the locked exit), the mixed overview (completed, current, available and locked nodes), and the Dead Coast region view with the real areas (4 of 7 explored, the player, the depot objective and both exits). The Dead Coast shot was taken with the map pointed at Dead Coast by a script; the world behind the dimmed screen is still Outpost 17, because Dead Coast cannot be entered through the real exits until the real scene is wired. Defects found and fixed: the objective label covered the area name; the exit label sat under the legend strip; the unlock hint was cut off; route lines ran through the labels.

## Known limits
- The Dead Coast and Blackwood regions are 245 m and 270 m long, so the region view is a tall narrow strip that is small on a wide window (about 190 px wide at 1280x720); zoom and pan help. A rotated or wider fit is not built.
- In the Dead Coast shot, the "To Blackwood (locked)" label overlaps the "?" fog box beside the top exit, and the depot label overlaps neighbouring fog boxes. Readable, but cluttered near the top.
- The Research Complex layout is a placeholder.
- The region content scenes are not wired into travel yet (see `docs/CAMPAIGN_FLOW.md`): the map reflects the real layouts and the campaign flags, but today travel still lands in the stub scenes.
- No minimap is drawn during play.
- Not tested: touch dragging and pinch zoom on a device, gamepad right-stick panning with a real pad (the code reads the stick axes; only the no-pad path ran), Android and web.
- At 800x360 the toolbar wraps to a second row and the canvas is the remaining height (the test enforces at least 150 px tall).
- The F3 stats overlay draws over the screen title in debug windows (this affects every full-screen RPG screen).
- A save made before this change simply has nothing discovered except the arrival areas.
