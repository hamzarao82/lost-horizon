# Facility components and Research Complex enemies (Milestone 8, building blocks)

Status date: 2026-11-07. These are reusable parts for the Research Complex. **The region itself is not built**: no scene uses these components yet, and no mission refers to them. Legend: **Verified** = covered by a test that was run; **Not tested** = no test or no human check.

## 1. Credential model
Three levels, saved as world flags with underscores: `credential_admin`, `credential_medical`, `credential_lab`. Every saved id in this milestone uses only `a-z`, `0-9` and `_` and stays within 48 characters, because `WorldState` drops anything else when a save is loaded (found while building Milestone 7). `FacilityIds.is_saveable()` is the check, and the tests scan every id the components write. Per-region flags use `RegionFlags.key(&"research_complex", flag)` (`research_complex_<flag>`); one-time claims use `PersistentIds` (saved with the region state).

## 2. Components (`scripts/regions/research_complex/`)
| Component | What it does | Status |
|---|---|---|
| `SecurityDoor` (extends `Door`) | Needs a credential flag; the locked caption names it ("Access denied: admin credential required"); opens once; open state is kept by the Door's own flag and a `PersistentIds` claim | Verified (locked, unlock, open, reload keeps it open, the claim alone keeps it open, another door stays shut) |
| `ResearchTerminal` (extends `Terminal`) | Optional power flag and credential level, separate locked messages ("no power" / "medical credential required"); first read sets `doc_<id>_found` (Progression already pays its discovery XP once for that flag; no XP is added here, to keep a single source) and marks the read claim | Verified (lock states, XP paid once, no second payout after reload) |
| `AccessPanel` | A swipe panel that grants a credential level once; it can require a flag first | Verified (dead until the keycard, grants once, reload keeps the credential and the panel spent) |
| `MultiStepPuzzle` | Base: ordered or any-order steps, per-step saved flag, completion signal and flag, `capture_state` and `restore_state`. A wrong input only resets the current step's loose progress; finished steps are never undone; a damaged save with only a late step flag restores fully | Verified |
| `PuzzleSwitch` | A button, lever or terminal face that forwards `input(switch_id)` to a puzzle | Verified through the two puzzles' input methods; not exercised as an in-world Interactable with a player |
| `LabPowerPuzzle` (Puzzle B) | Four breakers must match the pattern on a wall display, then a lever; a correct pattern locks in; a wrong lever pull switches the breakers off and loses nothing finished; a hint text exists for a facility document | Verified, including capture and restore at each of three stages |
| `ContainmentOverride` (Puzzle C) | Three terminals within a 45 s window after the first, in any order; when the window runs out only the unfinished window resets; then a release lever; the lever pressed too early only reports | Verified (expiry, restart, no regress, restore mid-window starts fresh, restore after terminals and after release) |
| `ContainmentControl` | Console with a lamp: red locked, amber window open, green released | Verified (lamp colours); look not reviewed in a screenshot of a full room |
| `FacilityEnemySpawn` | Spawns a config's enemy once (stats applied before entering the tree), writes a cleared claim when it dies, respects the global patroller cap for patrolling configs with a route, and puts a cleared elite's unique reward back if the save does not own it yet | Verified |
| `MissionTrigger` | An area trigger that fires one quest event (`WorldState.area_entered`) once and remembers it | Verified through `fire()`; the physical body-entered path is not tested |

Two limits to know: the containment window is not saved (after a reload it simply starts fresh), and the puzzle components have no in-world layout; they are logic plus small visual shells.

## 3. Enemy configurations
Enemies stay the existing `Enemy` framework. A `FacilityEnemyConfig` resource (`resources/enemies/facility_*.tres`) names a base scene and the stats copied onto it before it enters the tree.

| Config | Base | Notes |
|---|---|---|
| `facility_security_guard` | `PatrolSoldier` | 70 HP, facility tint |
| `facility_heavy_guard` | `HeavySoldier` | 180 HP, speed 2.0 (guard 3.2), stagger resistance 0.7, shield bash |
| `facility_experimental_subject` | `ExperimentalSubject` (new, extends `Enemy`) | 90 HP, speed 4.6, no patrol, wakes at 9 m, erratic sidestepping, lunge |
| `facility_elite_subject` | `EliteExperimentalSubject` (new, extends `Enemy`) | 300 HP, mini-boss, three attacks, unique reward |

`enemy.gd` was not changed.

### Attack table (frame data from `resources/attacks/*.tres`, 60 frames per second)
| Attack | User | Telegraph | Damage | Recovery or punish |
|---|---|---|---|---|
| Shield bash | Heavy guard | 40 frames (0.67 s) | 24 | 44 frames (0.73 s) |
| Lunge | Subject | 26 frames (0.43 s) | 14 | 30 frames (0.50 s) |
| Leaping claw | Elite | 42 frames (0.70 s), ground marker | 20, landing radius 2.6 m | 40 frames (0.67 s) |
| Ground slam ring | Elite | 40 frames (0.67 s) | 18, only on the ground (jump it) | 36 frames (0.60 s) |
| Charge | Elite | 48 frames (0.80 s) | 18, once | wall stun 1.5 s, open-floor stun 0.8 s |

Elite tells (seen in real screenshots on a neutral test floor): the claw shows a red ground marker where it will land and the model turns red during the telegraph; the ring shows a red disc of its full 4.5 m radius for the whole telegraph and removes it when released; the charge shows a red strip along its path.

Elite behaviour: attack weights claw 3, ring 2, charge 1 with distance gates (claw needs 3 to 10 m, ring needs the player within 5 m, charge needs 5 m or more); the same attack never runs three times in a row; only the heavy finisher interrupts it (super armor); it never patrols; defeat removes any live ring hazard.

Unique reward: `containment_sigil` (accessory, unique, region `research_complex`, icon generated by `tools/gen_icons.gd`). It is claimed by the inventory at pickup, not at drop, so dying and reloading before taking it cannot lose it (the spawn point restores a cleared elite's pending reward). It is not in the elite's loot table; the table only adds a medkit and credits.

## 4. Test results (2026-11-07, headless)
- `facility_components_check`: 95 checks, 0 failed.
- `experimental_enemies_check`: 47 checks, 0 failed (repeated runs; weakening the claw telegraph to 0.33 s makes it fail, as it should).
- Related suites rerun on the branch: `run_tests` 72, `patrol_check` 24, `boss_check` 20, `warden_design_check` 42, all 0 failed; `quest_check` 125 and `playthrough_bot` 63 also pass.
- The enemy test fights the real Player on a private floor: real hits kill, loot drops, damage per attack use is at most one hit, the claw lands within 1 m of its marker, the charge stops at a wall without tunnelling and leaves a stun of at least 1.4 s, the subject never enters a patrol state, a second elite never drops the reward again.

**Bug the tests found while building:** the subject approached to 4.7 m and then circled at that distance, so it never came within its 4.2 m lunge range and never attacked. Movement now closes in whenever its cooldown is ready.

## 5. Not done and not verified
- No Research Complex scene, mission data or layout uses these parts yet.
- The elite's attacks, the heavy guard and the subject use existing animation clips and the soldier model; nobody has watched the fight. Balance (health, damage numbers, attack weights) is untuned and unplayed.
- Screenshots (door, terminal, panel and containment console on a bare test floor; the elite claw and ring telegraphs) are in the author scratch folder only; the components are plain boxes and the room is empty, so this says nothing about how a finished wing will look.
- The elite does not show the boss health bar (it is in the group `miniboss`, not `boss`).
- Ranged enemies (the Facility Commander) are not part of this work.
- Web and Android were not run.
