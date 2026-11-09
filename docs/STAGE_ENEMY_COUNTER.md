# Stage enemy counter ("Enemies left")

Status date: 2026-11-09. **Implemented and tested** (`tests/stage_enemies_check.gd`, 40 checks). Not played by a person.

## Why
A tester played Dead Coast and said the enemies-left count was not showing properly. Measured cause: on arrival there were 4 live enemies, but the HUD label was empty, because it was hidden in every region except Outpost 17 unless a stage wave encounter ran.

## What the player sees (later regions only)
| Situation | HUD text |
|---|---|
| A stage wave encounter is running | `Wave n/N  Enemies: m` (unchanged, counts only that encounter's enemies) |
| Otherwise, enemies of the stage remain | `Enemies left: N` |
| Enemies existed in the stage and none remain | `Area clear` |
| A region with no enemies at all | nothing |
| Outpost 17 | the arena label `Wave n/5  Enemies: m` (unchanged) |

## The rule
`N` = living enemies now + members of lazy sources that have not spawned and are not cleared. Implemented in `scripts/world/stage_enemies.gd`, no per-region code.

- **Alive now:** every living enemy in group `enemies` except the enemies of the stage's wave encounter (they have their own counter).
- **Not spawned yet:** `PatrolGroup` (all members, until it spawns), `BlackwoodEncounter` (ambush members until it springs and while not cleared), `FacilityEnemySpawn` and `FortressSpawn` (1 each until they spawn, unless cleared), `StageBoss` (1 until spawned, unless defeated).
- A spawned enemy is counted once (alive), a waiting one once (pending), so the number does not move when a squad streams in, and a boss counts once.
- Reload: cleared squads, spawns and bosses stay cleared (world flags and `PersistentIds`), the rest respawn in full, so `N` after a reload equals the real members minus the cleared ones.

`PatrolGroup` and `BlackwoodEncounter` join the group `stage_enemy_sources` in `_ready` (one line each); the other sources already had groups.

## Measured totals on arrival (fresh game)
Dead Coast 14, Blackwood 14, Research Complex 14, Iron Fortress 19.

## Limits
- Counts hostile members, not their difficulty; a boss is one enemy.
- Squads that cannot spawn because of the four-patroller cap still count as left until they spawn.
- Nobody has played it; wording and placement are unjudged. The Iron Fortress hold point sits in the barracks, so garrison enemies are counted as stage enemies, not as wave enemies.
