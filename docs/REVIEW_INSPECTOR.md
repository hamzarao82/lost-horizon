# Review Inspector

A development tool for LOOKING at the game. It is not part of the game: it lives in `tools/review/`, and `export_presets.cfg` excludes `tools/*` from every release preset (`tests/review_inspector_check.gd` fails if that ever changes). Its home is the separate Review Hub folder (`GitHub\lost-horizon-review-hub`), which opens it with `Open Inspector.bat` or the desktop shortcut "Lost Horizon - Inspector".

## What it does
- Loads the real world (`Main.tscn`) and replaces the camera with a free-fly camera. The player stays as a scale reference but is inert; enemies are frozen by default (toggle).
- Region selector (all five regions, unlocked in memory only) and a "Jump to..." list: Outpost 17's four areas and named spots, or each region's entry points.
- Labels for enemies, pickups, interactables, doors, barrels, triggers and patrol groups, each with a toggle and a count. Labels fade out with distance. Outpost 17 spawns its enemies when the player approaches, so at load its patrol groups mark the encounters.
- A collision overlay (translucent tint over every collision shape).
- Left click selects an object (labelled things first, then a ray) and shows its class, id, region, position and groups.
- **Pin**: a decision (change / keep / cut), a priority and a note, saved as `PIN-<date>-<n>.json` plus a screenshot into the hub's `review-data/` folder. A pin holds the target, the camera position, the game build stamp and status `open`. **Screenshot** saves a plain screenshot.

## Controls
Right mouse + WASD fly, Q / E down / up, Shift fast, mouse wheel changes the speed, left click selects, F1 hides the panel.

## Safety
- It forces `SaveManager.test_mode`, so no save is ever written to the real file; the test compares the real save's size and time before and after.
- Pins go to the folder in the `LH_REVIEW_DATA` environment variable (the hub's launcher sets it).

## Snapshots (Phase 2)
`tools/review/snapshot.gd` (scene `snapshot.tscn`) visits every region, takes screenshots (a clean overview with fog off, a labelled overview, and one per named spot or entry point) and writes the list of every labelled object (`objects.json`) and the per-category counts (`stats.json`). Object ids are stable between runs (Godot's auto-generated `@Node@12` names are replaced by `<name>#<x>_<z>`), which `tests/review_snapshot_check.gd` enforces. It is run by the hub's `update-hub.ps1` / `Update Hub.bat` with `LH_SNAPSHOT_DIR` set; it needs a window (headless runs cannot take screenshots, so the test covers the data only).

The hub wraps each run in a snapshot folder with a manifest (commit, build label, Godot version, asset fingerprints) and compares two snapshots: screenshots side by side, objects added / removed / moved, count changes and changed assets. Pins whose object is missing or moved in the latest snapshot get a badge.

## Holo Bay data (Phase 3)
`tools/review/holo_export.gd` (class `HoloExport`, run headless by `export_holo_data.gd`) writes `items.json` (all items with kind, rarity, slot, the weapon-identity numbers, armor, value, description, and the model and icon files), `attacks.json` (every attack with its frame data, damage, telegraph time and owner) and `characters.json` (the player and every enemy scene with its stats, tactics flags and model file) from the game's own resources. The 3D models themselves are already GLB files (characters, weapons, armor, the environment kit, props): the hub copies them byte for byte and fingerprints each one, so a graphics upgrade shows up as "changed". `tests/review_holo_data_check.gd` (17 checks) covers the counts and that every model and icon path points at a real file.

## Phase 4: regions, sounds, UI screens, effects
- **Regions** (tools/review/region_export.gd, export_regions.tscn): every region is exported as one glTF from the live world plus a regions.json (bounds, what was left out, every labelled object). Shader materials become flat colours, vegetation is merged and thinned, the sea is left out. Test: tests/review_regions_export_check.gd (44 checks).
- **Captures** (tools/review/capture_ui.gd, capture_fx.gd; windowed only): 37 UI screens as 1280x720 PNGs and 19 effects as four-frame filmstrips. hit_stop and weapon_trail are not captured (no picture / needs a live swing). Test: tests/review_capture_check.gd (398 checks).
- The hub's Holo Bay shows them as Regions (labelled dots, pin an object with its position), Sounds (waveform, play, stats), UI screens and Effects.

## Found by the captures, fixed
The pause menu was taller than 1280x720 (Restart, Main menu, Settings and Quit were cut off). It is now two columns; tests/ui_layout_check.gd checks it fits at 1280x720, 1600x720 and 800x360.

## Not done yet
Nobody has heard the new sounds or played the new opening in a real window; Android needs a device.
