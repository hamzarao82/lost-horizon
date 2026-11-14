# Milestone 5 (Opening series): The Perimeter. Infiltration, security and the first real combat challenge

Status date: 2026-11-14. This is the brief, an audit of what the project already has, and a plan. **Nothing for this milestone is built as a unit.** It follows "The Hidden Settlement" (`MILESTONE_HIDDEN_SETTLEMENT.md`, plan only), "The Trail" and "Stranded" (see their status). Legend: **Exists**, **Partial**, **Not built**, **Verified**, **Not tested**.

## 1. Scope
A compact perimeter section with two viable routes to one progression point: a quiet route (cover, bypassing a patrol) and a direct route (fighting a small security position). Guards that notice sensibly, a fair first real fight using existing combat, at least two interactions with real effects, rewards from the existing loot systems, objectives updated, ending at the first interior section with a new lead and no premature rescue mission. 6 to 10 minutes.

## 2. Audit
| Brief item | What the project has today |
|---|---|
| Perimeter geometry to reuse | **Exists, but not as described.** Area A, "Outer Perimeter" (z 30 to 80), is a beach strip with a checkpoint desk whose log reads "Gate watch abandoned. Patrol 3 pulled north without orders." It is **written as abandoned**, which contradicts a live, patrolled security perimeter. Area B, "Military Compound" (60 by 60), is the fenced courtyard where the five-wave arena runs. A door `DoorBC` joins the compound to Area C and is opened by an access card reader. |
| Fences, guard posts, makeshift barriers, storage, small structures, cover | **Partial.** The dressing kit (`arena_decor.gd`, `area_dressing.gd`) provides walls, crates, sandbags, hazard stripes, pipes and a generator shed; vegetation scatter provides bushes and rocks. No ready "guard post" or "makeshift barrier" prop. Cover is geometric only (no cover-system) |
| Two routes (quiet and direct) that rejoin | **Not built.** Outpost 17's first areas are linear (beach, gate, courtyard, door). A second route would need new geometry and a rejoin point |
| Patrolling guards that notice sensibly | **Exists.** `PatrolGroup` with routes, `DetectionComponent` (sight cone, suspicion, search, noise), return-to-patrol behaviour, a cap of four active patrollers with a retry for held-back squads, and the ally-alert hook. Area C and D already have patrols started on the player's approach. **Area A has no live guards** |
| Not detecting through walls or at unreasonable ranges | **Exists as design** (sight cone and line-of-sight checks) and is covered by detection suites; not re-verified for a new layout |
| Reacting to nearby disturbances | **Partial.** A noise input exists in `DetectionComponent`; fights, thrown objects and distractions are not authored |
| First real combat challenge: attack, dodge, timing, telegraph, armor, healing | **Exists in systems.** Since the M11 merge, enemies can opt in to flanking, spacing, retreat, reinforcement and a guard stance, but **all of these are off by default** and a worker was turning them on for the real configs when this was written. No encounter is authored as "the first real fight"; the existing first fight is the courtyard arena wave set, which is a different shape (waves, a boss) |
| Fair, not inflated health | **Exists as a rule**: the balance simulation (`balance_sim_check`) and boss fairness test protect numbers; for regular enemies the table gives time-to-kill and damage-taken estimates from formulas, not a playtest |
| Environmental interactions with real effects | **Exists.** Interactables: `Door` (with `lock_reason` and a required flag), `CardReader`, `Keycard`, `SupplyCrate` (with persistent ids and loot), `SecurityPanel`, `PowerSwitch`, `BreakerSwitch` and `SequencePuzzle`, `Checkpoint`, `LoreDocument`, `Terminal`. All are wired to flags, inventory or doors. A gate or alternate entry made from these would be real, not decorative |
| Rewards from the existing loot and inventory systems | **Exists** (`LootTable`, unique claims, supply crates, medkits, armor). Outpost 17 already has crates in B and C; none are placed for this section |
| Explosive barrels as a distraction or tool | **Partial.** The component exists (`explosive_barrel.gd`), but **no region places one yet** (a worker was placing them when this was written). It would fit the quiet and the direct route |
| Checkpoints, save, reload resets enemies sensibly | **Exists.** `Checkpoint` interactables, atomic saves, persistent ids, enemies persisted through region state and reset policy |
| Enemies navigate correctly, no unintended gaps in the perimeter | **Exists as a method** (physics route probes, keep-clear tests, keep-in boundary checks); a new layout would need its own |
| Objectives "Recover your payment", "Find a way inside", "Get past the security perimeter", "Search the settlement" | **Not built.** None of these exist (see Stranded and Hidden Settlement). The old campaign starts `first_signal` on arrival |
| Audio: guard footsteps and voices, fence and gate sounds, machinery, ambient music | **Partial.** Footsteps, combat impacts, an enemy alert sound, door and terminal sounds (the latter two were listed as missing earlier; check before relying on them), the outpost ambience loop. **No guard voices, fence or machinery sounds.** The audio budget is full, and generated sounds are unlistened |

## 3. Contradictions to resolve first
1. **The abandoned-checkpoint log in Area A** says the gate watch has left. The brief needs a live perimeter. Either re-word the log and populate the gate with a patrol (small text and data change), or place the live perimeter just beyond Area A (new geometry).
2. **The courtyard arena** (Area B) is the first big fight in the real game and is already tuned as waves plus the Warden. "The first real combat challenge" in this brief must not be confused with, or run on top of, that arena; the plan should sit in front of it and end at the compound gate.
3. **The first mission** (`first_signal`, 15 objectives) begins on arrival. It needs to be gated or reworded so it does not start while the player is still at the perimeter.

## 4. Planned work
| Phase | Work | Status |
|---|---|---|
| 0 | Prerequisites: the Stranded fixes, the Trail strip and the Hidden Settlement approach | not started |
| 1 | Resolve the three contradictions above; add `area_a0` or extend Area A with a second route (a flanking path through bushes and rocks) rejoining before the compound gate | not started |
| 2 | Guards: one patrol of two soldiers on the main route and one lookout near a post; detection tuned so the quiet route is genuinely possible; the real enemy configs' tactics (flank, spacing, retreat) tested on this fight before relying on them | not started |
| 3 | Interactions: a gate that is opened by a crank or switch on the quiet route, a locked supply shed opened by a key or a breaker, and a security panel that disables a searchlight or alarm; each a real flag or door change | not started |
| 4 | Rewards: one supply shed with a medkit and armor, one guard drop with a unique item, persisted with unique ids | not started |
| 5 | Objectives: "Get past the security perimeter." and "Search the settlement." added in front of the old chain and persisted | not started |
| 6 | Tests: both routes reach the same point (a route probe with and without fighting), detection does not see through walls, save and reload at each step, the guard states reset as designed, no gaps in the fence, regression of earlier suites | not started |
| 7 | Audio: reuse existing sounds only; place sounds only where they already exist | not started |
| 8 | Windows and browser checks, performance measurement, report | not started |

## 5. Risks and honest limits
- Outpost 17's early areas were authored as an abandoned site, and the story and tests elsewhere rely on that; changing them touches quests and documents.
- The enemy tactics are new and unplayed; making them the basis of a "fair" first fight needs a human playtest.
- Cover and stealth are thin: sight cones and suspicion exist, cover-seeking and takedowns do not, so "quiet route" depends on geometry and timing rather than a stealth system.
- Missing sounds (voices, fence, machinery) and a full audio budget.
- The opening series is unplayed from the Stranded handoff onward, so this milestone would be built on untested ground.
- Pacing, difficulty and fun can only be judged by a person.

## 6. Acceptance tracking
All twelve criteria in the brief are **not started**. Criterion 12 (Windows and browser builds remain functional) holds today for Windows by the export smoke test and is untested for the browser build of the current commit; criterion 11 (save and progression work) holds by the full regression.
