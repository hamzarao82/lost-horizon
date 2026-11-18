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

## Not done yet
The Holo Bay: characters with all their animation clips, weapons, items, props, effects, UI screens and sounds in one 3D viewer, and before/after comparison of upgraded assets.
