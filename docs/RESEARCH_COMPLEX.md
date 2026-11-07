# The Research Complex (Milestone 8, the region)

Status date: 2026-11-07. Legend: **Verified** = covered by a test that was run (headless unless stated) or a screenshot that was looked at; **Not tested** = no test and no human check.

## 1. What exists
A fourth region reached from Blackwood through the real `RegionManager`. It follows the pattern of Dead Coast and Blackwood: a self-contained builder (`ResearchComplex`) wrapped by a region adapter (`ResearchComplexRegion`), data in `resources/regions/research_complex.tres` (now pointing at `scenes/regions/ResearchComplexRegion.tscn`, no longer the stub). Local coordinates: arrival at the south end (+z), the facility runs north (-z).

| Area | Id | What is in it |
|---|---|---|
| A Research Perimeter | `rc_perimeter` | fence line, road with a barrier chicane, checkpoint hut (logbook terminal and keycard rack), four guard towers, two vehicles, crates, an optional cache, three guards (two patrol, one stands), the admin facade and its door |
| B Administration Wing | `rc_admin_wing` | lobby with reception desk, offices, archive, security control room, conference room, the medical door; security console, archive breaker, archive terminal, medical access panel, optional cache and memo |
| C Medical Research Wing | `rc_medical_wing` | exam rooms, records room, observation ward behind a window, medical storage corner; trial notes, roster, optional notes; two subjects in an ambush; the containment door |
| D Containment Sector | `rc_containment` | two rows of cells with damaged doorways, two electrified floor strips, three override consoles, the lever and status lamp, the sealed holding chamber with Subject Zero, the laboratory panel and door |
| E Central Research Laboratory | `rc_lab` | main hall with benches and tanks (cover points for the Commander), data archive (west), power control room with breaker wall (east), the final chamber behind a power door |
| F Underground Exit | `rc_underground` | a service hatch in the final chamber, eight steps down to a tunnel that ends at a sealed road gate |

Each area is its own modular node (`Area_<name>`) built by its own function into one vertex-coloured solid mesh and one unshaded glow mesh (`ResearchComplexKit`), so Milestone 13 can replace an area's art without touching the gameplay parts.

## 2. Missions (the existing `QuestManager`, `resources/quests/research_complex/`)
| Mission | Required objectives | Optional |
|---|---|---|
| The Restricted Zone | find the entrance; deal with the perimeter guards (defeat them **or** slip past to the checkpoint); search the checkpoint; take the admin keycard; unlock the administration wing | the perimeter cache |
| Silent Records | find the archive; restore the security network; restore archive power; retrieve the records; get the medical credential; enter the medical wing; find the evidence of experimentation | survive the ward ambush; the conference cache; three papers |
| Containment Breach | enter containment; run the containment override (Puzzle C); survive the cell subjects; enter the holding chamber; defeat Subject Zero; recover the incident report | the override notes; the medical cache |
| Project Black Site | reach the laboratory; match the breakers (Puzzle B); defeat the laboratory security (two heavy guards and the Facility Commander); reach the final chamber; retrieve the data; learn where it leads; open the service hatch; reach the sealed exit | two laboratory papers |
Missions chain through `next_quest`. Every objective is event-driven and remembered, so steps may be done in any order the world allows. Rewards use existing items; the unique `containment_sigil` is Subject Zero's drop, not a quest reward. Completing the last mission sets `research_complex_region_complete` (read by the map and the campaign chain).

## 3. Puzzles and interactions (all built from the Milestone 8 components)
- **A, security access:** checkpoint logbook, then keycard rack (`credential_admin`), then the admin door. The medical credential comes from a panel that only works once the security console has restored the network. The laboratory credential comes from a panel in the holding chamber that only works once Subject Zero is down.
- **B, laboratory power** (`LabPowerPuzzle`): four breakers must match the pattern on the wall display, then the main lever; a wrong pull trips the breakers and loses nothing.
- **C, containment override** (`ContainmentOverride`): three consoles within 45 s, then the release lever; the elite's door opens when it completes.
- Floor hazard (`ResearchComplexHazard`): a 1.5 s cycle SAFE 0.6 s, WARN 0.5 s, ACTIVE 0.4 s; damage only in ACTIVE, at most once per window, avoidable by dodging or timing.

## 4. Enemies and placement (existing framework plus the Milestone 8 configurations)
Perimeter: three Research Security Guards (two patrol). Administration: two security guards (one patrols). Medical: two Experimental Subjects released by a trigger with a 1.5 s warning (caption and a creak sound) so the ambush is fair. Containment: three subjects wake when the player nears the cells, then Subject Zero (the elite; he is also put in the group `boss`, so the existing HUD boss bar and name show). Laboratory: two Heavy Facility Guards and the Facility Commander (ranged, uses five placed cover points). Cleared enemies are remembered through `PersistentIds` and never come back; Subject Zero's unique reward is put back once if a save does not own it yet.

## 5. Story
Sixteen original documents and terminal pages (`research_complex_story.gd`), consistent with the established lore: deliberate organised experiments on subjects who never consented; the containment failure was an order, not an accident; Project Black Site is bigger than this facility; the recovered route table points to the command behind the iron gate. The Director appears by title only, and the data's one destination leaves the next region open.

## 6. Persistence
Every id is underscore-only and at most 48 characters (`WorldState` drops anything else when a save is loaded; a test scans every id and proves a dotted flag is lost). Flags go to `WorldState`, claims to `PersistentIds` (saved with the region state), puzzle progress through `capture_state()` / `restore_state()`. The containment window itself is not saved: after a reload it starts fresh and can still be completed.

## 7. Test results (2026-11-07, headless)
| Suite | Checks | What it proves |
|---|---:|---|
| `research_complex_check` | 79 | six areas exist, every quest objective points at something the world produces, all ids saveable, a physics probe walks arrival to sealed exit (and the closed admin door stops it), no solid interactable on the route, hazard phases and damage timing, adapter and region data, map data matches the builder, mesh budget |
| `research_complex_missions_check` | 75 | all four missions through real interactions and real kills, in order and with another order, optional objectives stay optional, rewards arrive once, wrong puzzle input never blocks, the elite reaches the boss group, the exit early does nothing |
| `research_complex_persistence_check` | 38 | real `Main`, real travel, real save and load mid-mission and mid-puzzle: credentials, open door, taken cache, cleared guard, defeated elite and his reward (put back once), both puzzles finishable after reload, five round trips Blackwood and back with node counts at baseline |
Other suites rerun with this branch: see the final report; `region_check` and `region_save_check` were changed to use the generic stub scene explicitly because they tested the framework with the Research Complex stub.

## 8. Screenshots (windowed, real travel; six shots looked at)
Perimeter, administration wing, medical wing, containment with Subject Zero (boss bar and charge telegraph visible), central laboratory (Commander shot and aim line visible), final chamber. Draw calls measured in those frames: 81 to 147 (one frame at the perimeter showed 168). Visual verdict: **readable but placeholder**: flat vertex-coloured boxes, a strong blue cast in the laboratory, plain props. A first pass was too blue and had mirrored signs; the preset ambient and the sign directions were corrected and the shots retaken.

## 9. Fixes made along the way
- The detached Outpost 17 world-flow node kept listening to interactions and looked up an autoload by absolute path from outside the tree, which the engine logs as an error on every interaction in another region. It now does nothing while detached (`world_flow.gd`).
- The Research Complex stub is gone from the data; two framework suites select it explicitly.
- The route probe found two solid obstacles (the gate chicane and the reception desk) on a straight route; the route weaves around them as a player would.

## 10. Not done and not verified
- Nobody has played the region: difficulty, pacing, the ambush, Subject Zero and the Commander fights are unbalanced and unjudged.
- The art is placeholder; interiors are boxes with glowing strips and flat colour zones.
- No new animation clips: enemies reuse existing ones (the Commander has no firing pose).
- Audio: it plays the region ambience set up earlier and the existing creak cue; there are no facility alarms, door or terminal sounds of its own, and nothing was listened to.
- The old arena wave counter still shows on the HUD in this region, as in the other new regions.
- The Iron Fortress road is sealed: the exit leads nowhere yet (`research_complex_region_complete` is set).
- Web and Android were not run.
