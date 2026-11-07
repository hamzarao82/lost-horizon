# Campaign Flow (Milestone 7, connective tissue)

Status 2026-11-07. **Verified** = an automated test ran and passed. **Not wired** = built, but not connected to the real region content. Region scenes in `RegionData` are still the stub; this document says what connecting the real content needs.

## What exists
| Piece | File | Status |
|---|---|---|
| `CampaignFlow` helper node (created by `RegionManager`) | `scripts/regions/campaign_flow.gd` | Verified |
| Unlock chain through WorldState flags | same | Verified |
| Outpost 17 road gate (barricade and "ROAD CLOSED" sign beyond the south exit, removed when the road opens) | same | Verified by tests; **not seen in a screenshot** |
| Locked-road caption "The road is blocked." and other refusal texts | `CampaignFlow.refusal_text`, used by `RegionManager.refuse` | Verified |
| Bridge quest `leave_outpost` "The Road South" | `resources/quests/campaign/leave_outpost.tres` | Verified |
| Quest folders registered automatically | `QuestManager.QUEST_DIRS` (`campaign`, `dead_coast`, `blackwood`, `research_complex`) | Verified |
| HUD tracker pin for the bridge quest | `QuestManager.tracker_first` | Verified (not saved; re-derived) |
| Results screen hint "Next: Dead Coast" | `scripts/ui/results_screen.gd` | Added; checked by the existing screens suites, **not seen on screen** |
| Hand-off captions at unlock and first arrival | `CampaignFlow.CHAIN`, `ARRIVAL` | Verified (said once) |
| `CampaignFlow.mark_mission_complete(region, n)` for content | same | Verified |

## Flags (the contract; underscores only, at most 48 characters)
WorldState drops saved flags that are not `[a-z0-9_]` or are longer than 48 characters, so **a dotted name never survives a reload**. `campaign_flow_check` fails if any campaign flag breaks the rule and `campaign_bot_check` proves a real save and load keeps them.

| Flag | Set by | Effect |
|---|---|---|
| `mission_first_signal_complete` | QuestManager | unlocks Dead Coast, starts `leave_outpost` |
| `dead_coast_unlocked` | CampaignFlow (derived) | `RegionData.unlock_flag` of Dead Coast; removes the road gate |
| `dead_coast_arrived` | CampaignFlow on first arrival | completes `leave_outpost` (event memory counts it even if set earlier) |
| `dead_coast_mission_3_complete` | `CampaignFlow.mark_mission_complete(&"dead_coast", 3)` | unlocks Blackwood |
| `blackwood_unlocked` | CampaignFlow | `RegionData.unlock_flag` of Blackwood |
| `blackwood_mission_3_complete` | `mark_mission_complete(&"blackwood", 3)` | unlocks the Research Complex |
| `research_complex_unlocked` | CampaignFlow | `RegionData.unlock_flag` of the Research Complex ("access granted") |
| `campaign_said_<region>` | CampaignFlow | marks that the arrival line was already said |

Accepted aliases that also earn the next unlock: `dead_coast_region_complete`, `dead_coast_cargo_complete` (the Dead Coast content's own finish flag), `blackwood_region_complete`, `blackwood_research_complex_access` (the Blackwood content's own flag).

## Rules
- Missions 1 and 2 of a region mark flags only; **mission 3 earns the next region**.
- Exits back are always available once their region is unlocked. Leaving Outpost 17 detaches its nodes, so on return the Warden stays dead, the puzzle stays solved, claimed caches stay claimed and completed quests stay completed (tested through travel and through a real save and reload).
- Nothing is lost by leaving mid-mission: quest events keep counting while the player is away.
- The gate is built once per `Main`, only while Outpost 17 is the current region, and travels with its nodes.
- The bridge quest pays its small XP once (60, from `progression_config.gd` `quest_xp`).

## What connecting the real content needs (not done)
1. **Scene paths:** `resources/regions/dead_coast.tres` and `blackwood.tres` still point at `StubRegion.tscn`. The real scenes are `scenes/regions/DeadCoast_content.tscn` and `Blackwood_content.tscn` (both exist; a test checks).
2. **Region interface:** the content roots (`DeadCoast`, `Blackwood`) extend `Node3D`, not `Region`. `RegionManager.travel` instantiates the scene as `Region` and calls `enter`, `restore_state`; a thin `Region` wrapper (or making the roots extend `Region`) is needed. Their `enter()` already returns a `Transform3D`, which differs from `Region.enter(entry_id)`.
3. **Entry ids differ:** the framework data uses `from_outpost` / `beach_arrival` / `from_blackwood` (Dead Coast) and `from_coast` / `from_complex` (Blackwood); the content uses `beach_arrival` / `from_blackwood` and `from_dead_coast` / `from_underground`. The data files and the content must agree. The content's Dead Coast exit to Outpost 17 asks for entry `from_dead_coast`, which Outpost 17's data does not have (`start`, `from_south`).
4. **Exits:** the framework spawns exits from `RegionData.exit_points`; the content builds its own markers with `locked_flag`/`requires_flag`. Pick one source. Until then the content's lock flags (`dead_coast_cargo_complete`, `blackwood_research_complex_access`) are already accepted by the unlock chain.
5. **Saved state:** the content exposes `capture_state` / `restore_state`; they need to be called by the manager like `Region`.
6. **Quests:** the content's quests (`dc_*`, `into_the_blackwood`, `ghost_frequency`, `experimental_site`) load from `resources/quests/dead_coast/` and `blackwood/` automatically through `QUEST_DIRS`.

## Tests
`campaign_flow_check` (contract, flag rules and a real `WorldState.to_dict` / `from_dict` round trip, locked state, unlock and bridge, reward once, revisit state, gate built once, unlock chain and aliases, no softlock) and `campaign_bot_check` (plays Outpost 17, Dead Coast, Blackwood and the Research Complex access with real walking into exit areas, a save in Blackwood and a reload). Both fail when the flag names are made dotted (checked by changing them temporarily).

## Not done
- No screenshot of the road gate or the hint line; headless tests only.
- The Research Complex is still a stub; its "access granted" gate is the locked exit and the unlock caption.
- The real content is not wired in (above).
- The old arena quest chain (`restore_power`, `broken_perimeter`, `final_transmission`) still starts after the first mission; the tracker pin only keeps the bridge objective on top.
- Web and Android transitions are untested.
