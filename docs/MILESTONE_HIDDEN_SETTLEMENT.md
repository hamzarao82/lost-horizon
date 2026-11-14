# Milestone 4 (Opening series): The Hidden Settlement. First view of the outpost and infiltration setup

Status date: 2026-11-14. This is the brief, an audit of what exists, and a plan. **Nothing for this milestone is built.** It follows "The Trail" (`MILESTONE_TRAIL.md`, also plan only) and "Stranded" (`MILESTONE_STRANDED.md`, which has an open defect). Legend: **Exists**, **Partial**, **Not built**, **Verified**, **Not tested**.

## 1. Scope
The player leaves the wilderness, sees signs of human occupation, gets a distant reveal of part of the settlement from a viewpoint, can observe it, then reaches a guarded outer perimeter with one patrol and an alternative route. The objective "Recover your payment" gains the contextual step "Find a way inside." No settlement name, no leader, no antagonist, no deeper mystery, no assault, 3 to 6 minutes.

## 2. Audit
| Brief item | What the project has today |
|---|---|
| Reuse the existing Outpost 17 rather than duplicating it | **Exists.** Outpost 17 is the game's first region: Area A (Outer Perimeter, a beach with a checkpoint), Area B (Military Compound), Area C (Research Access Facility) and Area D (Command Center), built in code by `outpost17.gd`, `arena_decor.gd`, `area_dressing.gd`, `vegetation_scatter.gd`. Nothing needs duplicating |
| Reveal "a distant section" from an elevated viewpoint | **Not built.** There is no authored vantage point. The terrain of Outpost 17 is flat building ground. The Dead Coast has a 10 m cliff watchpoint reached by a ramp, but that is a different region |
| Signs of occupation: cut vegetation, footpaths, fences, cables, wooden structures, guard posts, smoke | **Partial.** The dressing kit has fences, hazard stripes, cables and a generator shed (interiors), crates, sandbags and a watchtower-style prop in places; **no smoke, no wooden shanty structures and no footpath decals** exist as ready props |
| Guards and workers visible at a distance | **Partial.** Patrolling soldiers exist (`PatrolGroup`). **There are no worker NPCs in the game** (the only workers in the project are the three capsule stand-ins in the beach mini-scene); the brief's "workers transporting supplies" needs a new simple NPC with no combat, plus a hidden-by-distance rule for cost |
| Distant NPCs cheap to run | **Not built.** Enemy AI runs per enemy per frame unless the opt-in scheduler (merged under M11) is switched on; it is off for every config. Ambient background NPCs would need a visual-only walker with no AI |
| Short observation moment, optional internal line | **Partial.** Captions exist (`Hud.show_caption`) and a radio line system; no "observe" trigger exists. A trigger volume plus a caption is enough |
| Approach area with cover, a visible boundary, one patrol, one alternative route, a landmark | **Not built.** Outpost 17's perimeter is the fence and gate of Area A; the new approach strip would sit before it |
| Stealth | **Partial.** Sight cone, suspicion, search and noise exist; no takedowns, no cover system |
| Objective "Find a way inside." | **Not built.** The campaign's first mission (`first_signal`) starts a different chain. Also "Recover your payment" does not exist yet (see Stranded) |
| Do not display the settlement's name | **Currently violated by the game.** "Outpost 17" is the region's `display_name` and appears in: the map screen status line ("Outpost 17: n of m places explored"), the save slot info the Load Game list shows, travel labels ("To Outpost 17") and the area banner system. **A player sees the name from the first minute of a New Game.** This has to be resolved (see section 3) |
| Region and scene transitions, streaming | **Exists.** `RegionManager` loads one region at a time with fades and saved per-region state; Outpost 17 is detached rather than freed (a known memory cost) |
| Navigation around the new area | **Exists as a method**: physics route probes and keep-clear tests per region; a new strip needs its own |
| Map | **Exists** (`map_screen`, region map data under `resources/regions/maps`); the new strip would need entries so it does not show undiscovered parts |
| Audio: machinery, voices, generator hum, wind, footsteps, tension music | **Partial.** The "outpost" ambience loop, footsteps, wind (menu wind sound) exist. **No machinery, voices or generator hum files exist**, and the 3 MB audio budget is full, so new files must be tiny or shared. The music modes added under M12 are pitch variants of one loop |
| Persistence of the objective | **Exists** through `QuestManager` save/load; the new objective text would be data |

## 3. Decisions needed before building
1. **The name "Outpost 17".** Either rename the region's visible `display_name` for the early game (for example "The Perimeter" until a story flag is set, then reveal "Outpost 17" later) or accept that the name shows. Renaming touches the map status, the Load Game list and travel labels; ids must stay unchanged so saves and tests keep working. This is the main story-safety item.
2. **Where the viewpoint is.** Options: a built-up mound (a few terrain boxes with a ramp) on the new trail strip, or a raised platform in Area A's approach facing the compound. The first keeps the reveal separate from the outpost's own space.
3. **Workers.** Build a minimal "worker walker" prop (a non-combat figure on a looped path, no AI, hidden beyond a distance) or reveal only guards and machinery. Recommendation: the walker, because "workers are being controlled" is the point of the reveal; but it is new code.
4. **Relation to the existing first mission.** The old arena quests and `first_signal` start on arrival. The new objectives should sit in front of them and hand over cleanly, or the first mission needs re-gating. The first mission's radio lines were already adjusted under M12 for the thief canon.

## 4. Planned work
| Phase | Work | Status |
|---|---|---|
| 0 | Prerequisites: the Stranded fixes and, from The Trail, the trail area and its end point | not started |
| 1 | Rename or mask the region's displayed name for the early game; update the map and save-slot labels; a test that the string "Outpost 17" is absent from the early-game UI | not started |
| 2 | Occupation signs along the late trail: cut stumps, fence runs, cable lines, a guard post prop, smoke particles (a few, quality-scaled) from existing kit pieces | not started |
| 3 | Viewpoint and reveal: a trigger volume, a gentle camera look-at or simply a clear sightline, a short caption about getting the bag back being harder than following three people, in the existing writing style | not started |
| 4 | Living settlement from a distance: guards on existing patrols seen across the gap; visual-only worker walkers with a view-distance cutoff; a distant generator hum and wind mix from existing sounds only | not started |
| 5 | Perimeter approach: a short strip with bushes and crates as cover, a visible fence line, one patrol, one alternative route, a landmark such as the watchtower; no forced fight | not started |
| 6 | Objective: add "Find a way inside." when the viewpoint trigger fires, persisted through the quest save; the old chain takes over at the entry point | not started |
| 7 | Tests: route probes for both approach routes; keep-clear; the name-hiding test; an objective save/load test; a performance check of the viewpoint (draw calls, active enemies); regression of earlier suites | not started |
| 8 | Windows and browser checks, measurements, report | not started |

## 5. Risks and honest limits
- The name is already visible in several places; hiding it is wider than the new area.
- No vantage point, no workers, no smoke and no ambient machinery sounds exist today; each is new content.
- Outpost 17 is detached, not freed, so adding scenery inside the same region adds to a memory cost already noted in `MILESTONE_012.md`.
- The audio budget is full; "machinery" and "guard voices" cannot be added as new files without trimming something.
- Pacing and feel (a "memorable reveal") can only be judged by a person.
- Everything before this milestone in the opening series is unplayed by a human, and the Stranded defect means the starting state may be broken.

## 6. Acceptance tracking
All twelve criteria in the brief are **not started**. Criterion 10 (name not disclosed) currently **fails** against the shipped game by the audit above, even before any new content exists. Criterion 11 (previous systems remain functional) holds today by the full regression (97 suites).
