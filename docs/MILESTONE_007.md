# Milestone 007: Dead Coast and Blackwood

Status date: 2026-11-06. **Nothing in this milestone is implemented yet.** This document is the audit-based plan. Legend: **Implemented**, **Partial**, **Documented only**, **Verified** (a test or screenshot was run), **Not tested**.

## 1. Starting point (what exists, from the repository)
- One world: `Main.tscn` with the Outpost 17 build (areas A to D, courtyard arena), assembled in code by `Outpost17`, `ArenaDecor`, `AreaDressing`, `VegetationScatter`.
- Regions are not separate scenes. There is no region manager. `WorldState` (area names, flags), `Teleport` (the player ability, not a scene change), and `QuestManager` (resource-driven quests, events, optional objectives, `mission_completed`) already exist.
- Save v3 has a `world` section (checkpoint id and position), `progression` and `inventory` sections, atomic writes and migration. It has **no** region id, region state or per-region collectible state.
- Progression (XP, attributes, skills), items, loot tables, crafting, upgrading, merchants and the RPG screens exist from Milestone 6. Combo extension and counterattack skills were being finished when this plan was written.
- Patrols (`PatrolGroup`, detection, suspicion, search) exist with one cap of four active patrollers. Enemy kinds: soldier, heavy, elite hunter, Warden.
- Art: Blender-scripted stylized GLBs, a small kit of props, five CC0 Poly Haven props and four CC0 ambientCG texture sets. Buildings are boxes with triplanar materials; characters are stylized low-poly. No licensed foliage, vehicles or wrecks exist beyond the kit.
- Audio is procedural (combat, UI, footsteps, ambience loop, radio, boss). There are no region-specific ambiences.

**Open items from earlier milestones that this milestone inherits:** web load about 42 s against a 30 s budget (a bisect was running when this was written), desktop frame rate below 60 FPS at High quality on integrated graphics, no human play-through, Android never run on a device. Two new regions will add load, so these must be addressed first or alongside.

## 2. Proposed architecture
| Piece | Decision | Reason |
|---|---|---|
| Region scenes | One scene per region (`scenes/regions/OutpostSeventeen.tscn`, `DeadCoast.tscn`, `Blackwood.tscn`), each with a root script implementing a small `Region` interface (`region_id`, `enter(entry_id)`, `exit_points`, `capture_state()`, `restore_state()`) | Only one region in memory at a time, per the brief |
| `RegionManager` autoload | Loads the target scene in the background (`ResourceLoader.load_threaded_request`, single-thread on web: slice work), moves the player, fades, unloads the previous region, applies region environment and audio | Reuses the loading-screen pattern from `Boot` |
| `RegionData` resource | id, display name, scene path, entry points, environment preset, ambience, unlock flag, map data | Data-driven; new regions need no code |
| Outpost 17 | Wrapped, not rewritten: the existing Main content becomes the first region scene; existing tests keep instantiating `Main` directly | Preserves the 43 passing suites |
| Persistence | `WorldState` flags namespaced per region (`dead_coast.checkpoint_1_found`); save v4 adds `regions`: current region, per-region state dictionaries (collectibles taken, encounters cleared, optional objectives, discovered locations); migration from v3 keeps everything and puts the player in Outpost 17 | No reward can repeat after reload |
| Encounters | Reusable `EncounterGroup` (extends the existing `PatrolGroup`): spawn rule, trigger, persistence (`cleared` flag saved), respawn policy (`unique` never respawns; `ambient` respawns on re-entry after a cooldown) | Matches the brief's persistence rules |
| Quests | New `.tres` quests (three per region) on the existing `QuestManager`; objectives are event-driven (area entered, interacted, item collected, flag, kill count) exactly like `first_signal` | No new quest system |
| Map | `MapScreen` reads `RegionData` and discovered-location flags; shows region, player position, objectives, landmarks; undiscovered areas stay hidden | Brief section 13 |
| Streaming of heavy content | MultiMesh scatter per region with view ranges and a quality scale, as in Outpost 17 | Android and web budgets |

## 3. Dead Coast plan
Seven areas: Wreckage Beach, Coastal Trail, Abandoned Checkpoint, Smuggler's Cove, Cliffside Watchpoint, Hidden Supply Depot, Exit toward Blackwood. Three main missions (Wreckage, The Silent Checkpoint, Lost Cargo) with the objectives listed in the brief; optional caches, logs, weapon components, rare materials, one optional enemy camp, one hidden route. Enemies: coastal patrol soldiers, armed guards, heavy soldiers, two patrol groups, one guarded depot. Rewards scaled one step above Outpost 17 (region-tagged loot tables, a unique weapon part and a unique armor piece).

## 4. Blackwood plan
Seven areas: Jungle Entrance, Overgrown Military Trail, Abandoned Patrol Camp, Research Perimeter, Hidden Communications Station, Experimental Testing Site, Research Facility Entrance. Three main missions (Into the Blackwood, Ghost Frequency, The Experimental Site). Ambush encounter, communications station power puzzle reusing the three-switch pattern with a different rule, testing-site infiltration, elite defenders, exit unlocking the Research Complex region (access flag only; the region itself is future work). Darker lighting must keep a minimum readability level (an automated brightness check on screenshots).

## 5. Story constraints
New material must not contradict existing documents: Outpost 17 was a signal and research site; the Warden is an earlier experiment; the first mission already exposes Project Black Site and the Director. Dead Coast reveals the shipment and the abandoned operation; Blackwood shows human experimentation and points toward the Research Complex without revealing the whole mystery.

## 6. Work phases
| Phase | Content | Status |
|---|---|---|
| 0 | Fix inherited blockers: web load budget, desktop frame cost; decide the asset approach (see risks) | not started |
| 1 | Region framework: `RegionData`, `RegionManager`, Outpost 17 wrapped, loading transition, save v4 with migration, tests | not started |
| 2 | Dead Coast: terrain, areas, encounters, three missions, side content, audio, tests | not started |
| 3 | Blackwood: same for the second region | not started |
| 4 | Map screen, region audio crossfade, persistence across regions, full-flow bot (Outpost 17 to Dead Coast to Blackwood), screenshots, performance measurement | not started |

## 7. Acceptance tracking
Every checklist item from the brief (Dead Coast, Blackwood, integration, visual quality) is **not started**. Rows will be filled with test names and counts as phases complete. A feature is not marked done because a scene or script exists.

## 8. Risks and honest limits
- **Art:** the brief asks for detailed foliage, wrecks, vehicles and structures at the quality of the reference images. The CC0 libraries reachable from this environment (Poly Haven props and textures) are limited; Quaternius and Kenney downloads were unreachable unattended. Without new assets from the owner or a much larger Blender modelling effort, the regions will use the existing kit, scattered CC0 props and procedurally built terrain, and will look stylized and low-poly, not like the references. This will be stated in the status rows.
- **Scope:** two full regions with three missions each is more than one session; the plan is phased so that a region framework plus one finished region is a valid stopping point.
- **Performance:** Outpost 17 alone misses the web load and 60 FPS budgets on integrated graphics; each region must stay within its own budget and the transitions must not hold both regions in memory.
- **Persistence bugs:** the highest risk is duplicate rewards across region changes; every collectible and unique reward needs a saved id, with a reload test.
- **Android and web** are untested for all Milestone 6 and 7 content.
- **No human playtest** of mission flow, balance or navigation readability has happened; automated bots prove reachability only.
