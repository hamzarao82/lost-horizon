# Save system

Local, versioned, ID-based (GDD section 20). Code: `scripts/core/save_manager.gd` (autoload `SaveManager`), `Inventory.to_dict()/from_dict()`, `WaveManager`, `PauseMenu`.

## File
`user://save_slot_1.json` (slot number is a variable, only slot 1 is exposed in the UI). Headless runs (tests) use `user://save_test_<pid>_slot_1.json` (one file per process, deleted on exit), so tests never touch a real save and parallel runs cannot collide. On web, `user://` lives in IndexedDB.

```json
{
  "version": 1,
  "saved_at": 1762000000,
  "next_wave": 3,
  "completed": false,
  "inventory": { "weapon": "military_machete", "armor": "heavy_combat_armor", "potions": 2 },
  "player": { "health": 55.0, "max_health": 100.0 },
  "defeated_bosses": ["warden"]
}
```
Items are stored by `item_id`, which is the file name in `resources/items/`. No node, resource or path is ever stored. Unknown ids, items in the wrong slot, and out-of-range numbers are ignored or clamped on load.

## Writing
`write_data()` writes the whole file to `<file>.tmp`, then replaces the real file. A crash mid-write leaves the previous save intact. (On Windows, Godot removes the old file just before the rename, so it is not a single atomic operation at the OS level, but a partial file is never left behind as the save.)

## Loading and failure handling
`load_game()` returns `false` instead of throwing:

| Case | Result |
|---|---|
| No file | `false`, `last_error = "no save"` |
| Not JSON / wrong shape / bad `version` | The file is moved to `<file>.bak`, `false`. The Load button then shows "no save". |
| `version` newer than this build | `false`, file untouched (a newer build can still read it). |
| Older `version` | Migrated step by step by `_migrate()` (v0 flat prototype layout -> v1), then sanitised. |

On success the data is queued in `SaveManager.pending_load / pending_data`; the caller reloads the scene.

## When the game saves
- **Autosave** when a wave is cleared (`next_wave` = the next wave) and when the arena is completed (`completed = true`, `next_wave = 1`, boss ids recorded). The HUD shows "Progress saved".
- **Manual:** pause menu -> Save (closes the menu first so the toast is visible). Saving mid-wave resumes at that wave's start; saving between waves resumes at the next.
- **Lifecycle (web/mobile):** `WM_CLOSE_REQUEST`, `APPLICATION_PAUSED` and `APPLICATION_FOCUS_OUT` autosave while a run is in progress.
- A dead player is never saved.

## Resuming into a new scene
`SaveManager` survives scene reloads, so it carries the resume state:

| Situation | What happens |
|---|---|
| Pause menu -> **Load** | `load_game()` queues the save, scene reloads. `Inventory` (created with the player) restores inventory and health; `WaveManager.start()` begins at `next_wave`. A completed save keeps the inventory and starts again at wave 1. |
| **Death** | `player.gd` reloads the scene. At every wave start `WaveManager` records a **checkpoint** (wave + inventory) in memory. The new scene restores that inventory with full health and starts the wave the player died on. |
| Pause menu -> **Restart** | `reset_runtime_state()` clears the queue and checkpoint: a fresh run from wave 1. |
| Quit and relaunch | Memory is gone, so a new game starts at wave 1; use Load to continue from disk. |

State is consumed exactly once (`consume_start_wave()`), so a later reload doesn't re-apply it. The HUD shows a one-shot notice ("Save loaded - wave 3", "Back to wave 3").

## Adding to the save
Add the field in `build_save()`, read it in `_sanitize()` with a default, bump `CURRENT_VERSION`, and add a `_migrate_N_to_N+1` step. Keep old fields readable.

## Tests
`tests/save_check.gd` (62 checks): round trip, no `.tmp` left, ids only, corrupt/newer/non-numeric handling, v0 migration, clamping, hostile item ids, restore into a fresh scene, wave resume, death checkpoint, autosave on wave clear, boss recorded on completion.
