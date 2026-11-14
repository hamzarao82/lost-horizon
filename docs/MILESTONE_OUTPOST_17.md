# Milestone 6 (Opening series): Outpost 17. Entering the Black Site

Status date: 2026-11-14. This is the brief, the inspection it asks for (done here, from the real project), and a plan. **Nothing for this milestone is built.** It follows "The Perimeter" (`MILESTONE_PERIMETER.md`, plan only) and the earlier opening documents. Legend: **Exists**, **Partial**, **Not built**, **Verified**, **Not tested**.

## 1. Scope
Connect the redesigned opening to the existing Outpost 17 region without building a second outpost: reveal the name naturally, show organized security and controlled worker activity, add a compact internal encounter, add the contextual objective "Search Outpost 17." beside "Recover your payment.", and reconcile the existing mission "The First Signal" so it is not started accidentally. The Warden, the research wing and the command center stay intact. 5 to 8 minutes.

## 2. Inspection report

### Existing Outpost 17 (reuse)
| Piece | Where | Notes |
|---|---|---|
| Region data | `resources/regions/outpost_17.tres`, `display_name = "Outpost 17"`, ambience `outpost`, no unlock flag | the first region; always available |
| Layout | `scripts/world/outpost17.gd`, `world_flow.gd`, `Main.tscn` | Area A "Outer Perimeter" (beach strip with an abandoned checkpoint desk), Area B "Military Compound" (60 by 60 fenced courtyard, arena, quartermaster, checkpoint B), Area C "Research Access Facility" (reached through `DoorBC`, opened by a card reader), Area D "Command Center" (through `DoorCD`) |
| Dressing | `arena_decor.gd`, `area_dressing.gd`, `vegetation_scatter.gd` | generator shed, pipes, cables, hazard stripes, crates, sandbags |
| Guards | `PatrolGroup` instances in Areas C and D (started when the player nears them); soldiers, heavy and elite configs | Area A has none |
| Arena and Warden | `WaveManager` five waves in the courtyard, then the Warden on wave 5; the arena is a state machine (M11) | must stay intact |
| Interactables | `Door`, `CardReader`, `Keycard`, `SupplyCrate` (ids and loot), `Checkpoint`, `LoreDocument`, `Terminal`, `PowerSwitch`/`SequencePuzzle` | reusable for the new beats |
| Region progression | `CampaignFlow`: bosses down open the Dead Coast road; the road quest `leave_outpost` | unchanged |

### The mission "The First Signal" (`resources/quests/first_signal.tres`)
- Fifteen objectives in this order of the data: reach the outer perimeter, investigate the abandoned checkpoint, find the source of the transmission, eliminate the hostile soldiers, locate the security access card, restore power to the communications facility, access the military terminal, discover the restricted research facility, unlock the next location, (optional) find the missing security log, enter the command center, defeat the command guards, read the Project Black Site file, defeat the Warden, take the Warden's reward, contact the outside from the command terminal. `next_quest` is `restore_power` (the arena chain).
- Its **description names the place outright**: "A weak military transmission is coming from Outpost 17. Find out who is sending it, and what they are hiding." Its journal and its "Project Black Site file" step reveal the project's name.
- It is the game's `FIRST_QUEST` and `MISSION_QUEST` (`quest_manager.gd` lines 45 to 49): the quest manager starts it automatically at the end of the intro for a New Game. Other code depends on its flags: `mission_first_signal_complete`, the reward table, `campaign_flow.gd`, `progression_config.gd`, the journal, the results screen and `blackwood_quests.gd`. Several tests assert its objective text and order.

### What conflicts with the new opening
1. **The first mission starts at arrival and says "Outpost 17" and "Project Black Site".** The brief wants the name discovered naturally and the project not revealed yet.
2. **Its first two objectives** ("Reach the outer perimeter", "Investigate the abandoned checkpoint") describe the arrival the opening now plays as its own sequence.
3. **"Find the source of the transmission"** gives the player a reason to come here that is not the payment.
4. **Area A is written as abandoned** (the checkpoint log), against the live perimeter in the Perimeter brief.
5. **The visible name "Outpost 17"** already appears in the map status line, the save slot info and travel labels (see `MILESTONE_HIDDEN_SETTLEMENT.md`), before any discovery.
6. **The radio lines** and some captions were adjusted under M12 for the thief canon; whether they say "Outpost 17" too early has not been re-read for this milestone.

### What should stay untouched
The five-wave arena and the Warden, the research and command areas and their doors and puzzles, the quest manager's event system, save and region state, the boss-opens-the-road flow, all item and loot data, and the quest ids and flags other systems read.

## 3. Proposed approach (needs your decision)
The safest route that honours "do not delete the mission":
- **Keep `first_signal` and every flag it sets.** Stop auto-starting it on New Game. Start it from a new trigger when the player reaches the compound's own entrance (the "name discovery" point), so its early objectives (reach the perimeter, investigate the checkpoint) are credited automatically by the existing "events done before a mission starts are remembered" rule.
- **Re-word, do not remove:** change the quest description so the name is no longer the first thing the player reads, and shift the "Project Black Site file" wording only at the step where the player reaches it (that reveal can stay, because it comes after the discovery).
- **Add a short opening quest** `search_outpost` in front of it, "Search Outpost 17.", pinned beside "Recover your payment." through `tracker_first`, completing when the player enters the compound entrance. All through the existing quest system; no new framework.
- **Name reveal:** a weathered "OUTPOST 17" sign (or a facility plate) as a prop at the compound entrance with a proximity trigger setting a flag `outpost_name_known`; until the flag is set, the map and save-slot labels show a neutral name (the same masking decision as in the Hidden Settlement document).
- **Payment trail:** two or three short clues in the compound (a guard's overheard line about "the recovered cargo", a storage door with a crate manifest, a worker path with scuffed ground) as `LoreDocument` and caption triggers, without naming the bag's location.
- **Internal encounter:** one small patrol of two to three soldiers near the compound gate using the existing configs (with the new tactics now live in the real configs), a side route through the storage yard, and a supply crate reward; the courtyard arena stays as the later big fight.

Questions only you can settle: whether the "Project Black Site" reveal inside `first_signal` stays where it is; whether the old arena chain (`restore_power`) is still the intended next step after the First Signal; and whether masking the region name is acceptable in the map and save list.

## 4. Planned work
| Phase | Work | Status |
|---|---|---|
| 0 | Prerequisites: Stranded fixes, the Trail strip, the Settlement view, the Perimeter section | not started |
| 1 | Gate the auto-start of `first_signal` behind the new trigger; keep its flags and tests green (a test that the quest does not start on arrival and does start at the trigger) | not started |
| 2 | Re-word the First Signal description and the early objective text; update the tests that assert the old text, listing each change | not started |
| 3 | Name discovery prop and flag, plus masking of the early region name in the map and save labels | not started |
| 4 | `search_outpost` quest and tracker pin; "Recover your payment." stays pinned | not started |
| 5 | Payment clues and one compound encounter with a reward, persisted by unique ids | not started |
| 6 | Route probe from the perimeter to the compound entrance and through the encounter; save and reload at each step; regression of the whole suite, including `mission_check`, `quest_check`, `campaign_bot_check`, `story_consistency_check`, `playthrough_bot` | not started |
| 7 | Windows and browser verification, performance measurement, report | not started |

## 5. Risks and honest limits
- `first_signal` is the spine of the old game and is referenced by many tests and systems; changing when it starts is the highest-risk edit in the whole opening series.
- Several earlier documents (`STORY_AND_MISSION_FLOW.md`, `CAMPAIGN_AUDIT.md`, the journal text) assume the player already knows about Outpost 17 and the transmission; they need a read-through for contradictions, which this document lists but does not resolve.
- The opening milestones 1 to 5 are unplayed by a person or unbuilt, so this milestone has no tested ground to start from.
- Unresolved story conflicts (to report, not to invent around): the transmission as motive versus the payment as motive; the abandoned checkpoint versus a live perimeter; the name appearing in system UI before the reveal.
- Pacing, difficulty and the quality of the reveal can only be judged by a person.

## 6. Acceptance tracking
All twelve criteria in the brief are **not started**. Criterion 2 (no duplicate settlement) and 10 (research wing, command center and Warden intact) hold today because nothing has been changed. Criterion 11 (save/load and progression work) holds by the full regression (97 suites). Criterion 9 ("The First Signal" reconciled) is the open design question in section 3.
