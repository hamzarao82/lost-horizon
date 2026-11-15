# Milestone 3 (Opening series): The Trail. First exploration, enemy encounter and combat introduction

Status date: 2026-11-14. This is the brief, an audit of what the project already has for it, and a plan. **Nothing for this milestone is built as a unit.** It continues "Stranded" (`MILESTONE_STRANDED.md`), which itself has an open defect (unplaced pickups) that must be fixed first. Legend: **Exists**, **Partial**, **Not built**, **Verified** (a test or screenshot), **Not tested**.

## 1. Scope and story rules
After the beach the player follows the guard and two workers inland, reads environmental clues, meets one or two patrolling guards, uses the improvised weapon, crosses one small obstacle, gets a real reward, keeps the objective "Recover your payment", and ends on a visual hint of a more developed place inland. No outpost, name, layout or leadership; no boss; no antagonist; the protagonist is not yet rescuing anyone. Target 5 to 8 minutes.

## 2. Audit of what exists
| Brief item | What the project has today |
|---|---|
| Where New Game puts the player | The real world is Outpost 17 (`scripts/world/outpost17.gd`, `world_flow.gd`). **Area A, "Outer Perimeter" (z 30 to 80), is a beach with a checkpoint at the beach gate, and Area B, "Military Compound", is straight inland.** So the first playable ground already is the outpost's own territory, with the compound immediately ahead. There is no separate wild inland trail between the beach and the outpost |
| A trail with clues (footprints, drag marks, dropped cloth, distant voices) | **Not built.** The Dead Coast has a "drag marks" objective and a coastal trail, but that is a later region (reached after Outpost 17), with its own story |
| Compact exploration area with optional spots, landmarks | **Not built** for this section. Outpost 17's four areas exist and are authored for a different purpose |
| Guards that patrol and can be noticed first | **Exists.** `PatrolGroup`, `PatrolRoute`, `DetectionComponent` with sight cone, suspicion, search and noise, an ally-alert hook, a cap of four active patrollers, and (since the M12 retry fix) a retry for held-back squads |
| Approach, bypass or fight | **Partial.** Suspicion and search states give a real chance to avoid detection; there are **no stealth takedowns** and no dedicated bypass route authored for this section |
| Combat teaching: attack, timing, dodge, telegraph, damage, defeat, health feedback | **Exists** in the combat system (three-hit chain, dodge with i-frames, enemy telegraphs, hit-stop, HUD health). Since the Combat HUD merge there is also a damage-direction wedge and a low-health warning. **There is no tutorial or coaching moment** for any of it in the opening |
| Weapon: improvised stick | **Partial.** `wooden_stick` exists (damage multiplier 1.0, same as the starting blade). It is not placed in the world (see `MILESTONE_STRANDED.md`); the player already starts with an improvised blade |
| Injured-state limits | **Exists** as `injured_speed_mult` and `attacks_locked` (handoff in `opening_beach.gd`); they are lifted only when the three survival items are found |
| Environmental obstacle (fallen tree, rocky passage, small climb or jump) | **Not built.** The player has jump and dodge. **There is no climbing, vaulting or mantling system** in the project; the nearest thing is the Dead Coast's cliff ramp |
| Reward: medkit, better weapon, loot container | **Exists as systems** (`Pickup`, supply crates with persistent ids, loot tables, unique-claim). No reward is authored for this section |
| Objective "Recover your payment" | **Not built.** The tracker pins the survival quest only; no quest mentions the payment |
| Evidence of a larger operation, ending with a hint of a developed place inland | **Not built** as an authored beat. The campaign already tells this story elsewhere (journal, documents), which conflicts with "do not reveal" if surfaced early |
| Audio: forest ambience, footsteps, voices, vegetation, awareness cues, impacts | **Partial.** Footsteps, combat impacts, the enemy alert sound and per-region ambience loops exist. **No forest ambience, distant voices or vegetation sounds.** Generated audio is unlistened, and the audio budget is full (3 MB) |
| Checkpoints and save | **Exists.** `Checkpoint` interactables, atomic saves, persistent ids, per-region state |
| Enemies not attacking through obstacles | **Exists** in the AI's line-of-sight and collision rules; not tested for a new layout |

## 3. The central design problem
The brief assumes a wild inland trail between the beach and a "more developed area" the player has not yet seen. The game's real first level already contains the beach, the checkpoint and the Military Compound (Outpost 17) in one continuous space, and the campaign's first mission (a radio signal to the command terminal) is built on it. Building The Trail therefore needs a decision, not just content:
- **Option A: a new small region.** Add a short pre-outpost trail area (about 60 to 90 m) between the beach and Area A's gate, inside the existing Outpost 17 region as a new area "A0", using the same builder pattern as Areas C and D. Cheapest and keeps one save region. The outpost's own geometry must stay out of view from the trail.
- **Option B: reuse Area A as the trail.** Dress Area A with clues and place one patrol, and treat the beach gate as the "inland hint". Smallest, but the Military Compound and the checkpoint are close enough to be seen from there.
- **Option C: a separate Region (`RegionData`).** Cleanest for isolation and for guaranteeing nothing of the outpost is visible; costs a region transition and a second set of save fixtures.

Recommendation: Option A, with the trail's far end showing only smoke or a distant light above the treeline, never a structure. This needs your decision before building.

## 4. Planned work
| Phase | Work | Status |
|---|---|---|
| 0 | Fix the Stranded defect: place the three pickups, make the failsafe grant everything missing, add "Recover your payment" | not started |
| 1 | Trail area: path, landmarks, clues (footprints, flattened grass, a dropped rag as decals and props from the existing kit, no UI markers), one optional side nook, builder file in the style of `outpost17.gd` | not started |
| 2 | Patrol: one or two soldiers on a route that crosses the trail, a flank that allows bypass, the player seeing them first (sight cone check); no new AI | not started |
| 3 | Environmental obstacle: a fallen log that can be jumped, with a longer way round (the smallest solution; no climbing system) | not started |
| 4 | Reward: a supply crate with a medkit and a better improvised weapon (a data-only item), persisted with a unique id and claim | not started |
| 5 | Objective updates: "Recover your payment" gains meaningful sub-steps (find the trail, deal with the guards, reach the ridge), updated by the existing quest events | not started |
| 6 | Ending beat: a view point with smoke or a distant light, a short caption, a checkpoint, and a flag for the next milestone | not started |
| 7 | Tests: route probe from the beach to the end of the trail with and without fighting; save and load at each step; no outpost visible from the trail (a camera or ray test against outpost nodes); regression of previous suites | not started |
| 8 | Audio: reuse existing sounds only, and place a forest-style ambience only if a quiet existing loop is suitable; no unlistened new files | not started |
| 9 | Windows and browser checks, performance measurement, report | not started |

## 5. Risks and honest limits
- The biggest risk is the story conflict above: the outpost is a few steps from the beach in the real level, so "do not show the outpost" is easy to violate by accident.
- No traversal system exists; the "obstacle" must be a jump or a detour, not a climb.
- Nobody has played the opening, so the starting condition for this milestone (injured, attacks locked) is itself unverified in play.
- Audio is generated and unheard; adding forest ambience would use up the audio budget.
- Pacing of 5 to 8 minutes cannot be judged without a person playing.
- The opening's earlier pieces use stand-in shapes; this milestone would be the first to use the real character in the opening's own world, so it will look different from the cinematic.

## 6. Acceptance tracking
All twelve criteria in the brief are **not started**. Criteria 5 and 12 (the improvised weapon works in combat; previous systems remain functional) hold today by existing tests; criterion 8 (the objective stays active) and 9 and 10 need the Stranded fixes and the new content first.

## 7. Status after implementation (2026-11-15)
Built together with the Hidden Settlement and Perimeter milestones, in Area A (decision 5 of `OPENING_DECISIONS.md`), by `scripts/world/opening_approach.gd` (`OpeningApproach`, one added hook line in `outpost17.gd`). **Implemented and tested** (`opening_approach_check`, 50 checks): footprints and two drag lines leading to the berm's direct gap, flattened-grass patches, a dropped rag, cut stumps; an earth berm (5.8 m) that screens the compound from the spawn with a direct gap (x -3..3) and a bushy bypass gap (x 24..28), verified by sight-line rays from the spawn camera; a fallen log (0.8 m, jumpable: apex 1.84 m) across the bypass; a guard shed; two patrols (two guards beside the gap, one at the gate) that wake with the opening; the quest `opening_trail` ("Follow the trail inland", optional "climb the rise and look ahead") that hands over to `opening_perimeter`. A route probe walks the direct way and the bypass to the same point. **Not done / not verified:** nobody has played it; the berm is a tan terraced block, not terrain; the old beach sign still reads "OUTPOST 17 - NO ENTRY" (another worker owns the sign); no new sounds (audio budget); the quest starts only after the beach hands control over (`opening_event_seen`), so existing saves without that flag never see it.
