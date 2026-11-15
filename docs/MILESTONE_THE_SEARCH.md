# Milestone 7 (Opening series): The Search. Restricted areas and the first real discovery

Status date: 2026-11-14. This is the brief, the inspection it asks for (done here from the real code), and a plan. **Nothing for this milestone is built.** It follows "Outpost 17" (`MILESTONE_OUTPOST_17.md`, plan only) and the earlier opening plans. Legend: **Exists**, **Partial**, **Not built**, **Verified**, **Not tested**.

## 1. Scope
Inside the existing Outpost 17: several meaningful locations to search (storage, guard station, worker supply area, a restricted corridor, the research entrance, an office), small discoveries that make the place feel wrong, real interactions (documents, a storage container, a terminal, an access card, a restricted door, an overheard guard conversation), a few varied encounters, and one concrete but incomplete discovery of an organized operation, using the game's existing lore. The payment trail advances: the bag was taken beyond the ordinary compound. No rescue mission, no new organization, no new project name. 6 to 10 minutes.

## 2. Inspection report (what Outpost 17 contains now)
| Area | Contents found in `scripts/world/outpost17.gd` and related files |
|---|---|
| A, Outer Perimeter | beach strip, an abandoned checkpoint desk with a "Checkpoint log" document, the beach-gate checkpoint |
| B, Military Compound | the fenced courtyard and arena, checkpoint B, supply crates `supply_crate_b1` and `b2` (a medkit plus a weapon or armor each), the quartermaster, the card reader that opens `DoorBC` |
| C, Research Access Facility (z -30 to -62) | a checkpoint desk with a clue document, an open **storage room** (west) described in code as "optional exploration reward", a **control room** (north-east) with a damaged panel console and the military terminal (`requires_flag = comms_power_on`), a **generator shed** with switch B, cover with switch C, crates, `supply_crate_c1`, the "Security log" (the ordered breaker puzzle B, A, C), the "Military record: Warden", an optional "Missing security log" |
| D, Command Center (z -62 to -92) | a command building with a console, desks, a **hidden back room** (north-west) screened by cover, the command terminal (usable only after the Warden falls), and the **"Project Black Site"** document |
| Guards | patrol groups started when the player nears Areas C and D (a patrol in C, two command guards in D whose defeat sets `patrol_d_guards_cleared`); soldiers, a heavy and an elite across the area |
| Interactables | `Door` with lock reasons, `CardReader`, `Keycard`, `SupplyCrate`, `Terminal`, `LoreDocument`, `PowerSwitch`, `BreakerSwitch`, `Checkpoint` |
| Mission wiring | `first_signal` objectives, in the data order: reach the perimeter, investigate the checkpoint, find the transmission, eliminate soldiers, find the access card, restore power to comms, access the terminal, discover the research facility, unlock the next location, enter the command center, defeat the command guards, read the Project Black Site file, defeat the Warden, take the reward, contact the outside. Flags it uses include `comms_power_on`, `has_keycard`, `boss_warden_defeated`, `mission_first_signal_complete` |
| Warden dependency | the command keycard and the final terminal depend on `boss_warden_defeated`; `CampaignFlow` opens the road on the Warden's defeat |

So the brief's wish list already largely exists in the real map under different names: the "storage room" is C's west room, the "restricted corridor" and "research wing entrance" are the DoorBC and Area C approach, the "administrative office" is the command building, and the "research wing" the brief tells us not to rebuild is Area C and the separate Research Complex region.

## 3. Mapping the brief to what exists
| Brief item | Status |
|---|---|
| Storage room, guard station, worker supply area, restricted corridor, research entrance, office | **Partial.** Storage room, control room, generator shed, command building and hidden room exist. **No guard station, no worker supply area** and no corridor props marked as such; they would be dressing and labels on existing space |
| Clues that the bag moved deeper, not in the first container | **Not built.** No document or conversation refers to a bag. Needs two or three new `LoreDocument` entries and one overheard line |
| Worker transport records, separate medical supplies, redacted documents, advanced equipment | **Not built.** The research and command documents are about the Warden and Project Black Site; there are no worker records. The Research Complex region later has sixteen story entries about the same themes, so some text can be adapted in tone, not copied |
| Reading a document | **Exists** (`LoreDocument`), journal entries exist |
| Inspect a storage container | **Exists** (`SupplyCrate`); a container holding a clue instead of loot needs a small variant |
| Terminal | **Exists** (military terminal behind `comms_power_on`; command terminal behind the Warden) |
| Access card or key found and used | **Exists** (`Keycard`, `CardReader`, `has_keycard`, `DoorBC`) |
| Restricted door | **Exists** (`DoorBC`, `DoorCD`, the lock reason text) |
| Short guard conversation | **Partial.** Captions and radio lines exist; **no positional overheard-conversation trigger** exists; a trigger volume plus two caption lines is the smallest version |
| Varied encounters: guards protecting restricted access, a bypassable patrol, a confined fight, a checkpoint | **Partial.** Patrols and fights exist; the new tactics (flank, spacing, retreat, guard stance) now apply to the real Research Complex and Fortress configs, **not to the bare Outpost 17 enemies**, which keep their old behaviour |
| Rewards through existing systems | **Exists** (loot tables, crates, unique claims) |
| First real discovery of an organized operation, using established lore | **Mostly exists.** The "Project Black Site" document already is that discovery, and it sits in Area D at the end of the First Signal. The brief wants a first, incomplete discovery earlier; this needs a decision (section 4) |
| Payment trail leads beyond the compound | **Not built**, and see the conflict below |
| Do not break the Warden or progression | **Holds today** |

## 4. Decisions and conflicts to settle before building
1. **Where the first discovery lives.** The only concrete lore document is "Project Black Site" in Area D. Options: (a) keep it there and add an earlier, vaguer discovery in Area C (a "personnel transfer" record that mentions restricted research and unnamed workers, without the project name); (b) move the existing document earlier. Recommendation (a): it respects "do not invent a contradictory project name" and leaves `first_signal` intact.
2. **The payment trail has no destination.** Outpost 17 contains no storage place for the bag, and the story beyond it sends the player to the Dead Coast road after the Warden. "The bag was taken beyond the ordinary compound areas" can lead to Area D's hidden back room, to the Research Complex region, or to the Dead Coast. Which one is the canonical answer is a story decision I cannot make from the code.
3. **The mission order.** The First Signal's own steps already cover most of this (find the card, restore comms power, read the terminal, enter the command center). The cleanest design is to add the new clues and a handful of quest steps as flavour in front of and around its existing steps, rather than a second chain; this depends on the Outpost 17 plan's gating decision.
4. **Bare Outpost 17 enemies.** If the deeper compound should fight with the new tactics, the Outpost 17 enemies need configs; today they are bare scenes.

## 5. Planned work
| Phase | Work | Status |
|---|---|---|
| 0 | Prerequisites: the opening plans from Stranded to Outpost 17, the First Signal gating decision, and the destination of the bag | not started |
| 1 | Name and place the missing locations: relabel and dress the guard station (checkpoint desk area) and a worker supply area (crates and bedrolls in the storage room) using kit pieces | not started |
| 2 | Clues: three short `LoreDocument` entries (transfer record, supply manifest with a redaction, a duty roster that mentions an unlisted detail), one overheard guard exchange (trigger volume plus two captions), one clue container variant | not started |
| 3 | Interactions with consequences: the card found at the guard station opens a restricted door; the terminal shows a redacted personnel list and sets a flag; a container yields a medkit and a clue | not started |
| 4 | Encounters: one confined fight at the restricted door, one bypassable patrol, one guard-and-supply spot; optional tactics configs for those enemies; no waves | not started |
| 5 | Discovery and trail: the earlier incomplete discovery document (option 4.1a) and a lead toward the chosen destination; objective text updates persisted | not started |
| 6 | Tests: every interaction changes real state; the card and door work; objectives update and persist; route probes through the new spots; reloading at each checkpoint; regression of `first_signal` and the Warden suites | not started |
| 7 | Windows and browser checks, performance, report | not started |

## 6. Risks and honest limits
- Most of the content here already exists as the First Signal's chain; adding a second layer of clues risks duplicating or contradicting it, especially around "Project Black Site".
- The destination of the payment is a story decision that the code cannot supply.
- No overheard-conversation system exists, and generated voice audio is not available; lines would be captions.
- Bare Outpost 17 enemies do not use the new tactics.
- Nobody has played the earlier opening milestones, so this one has no tested starting state.
- Pacing and discovery quality need a person.

## 7. Acceptance tracking
All twelve criteria in the brief are **not started**. Criteria 4 (access items work) and 10 (existing Outpost 17 content intact) hold today because the existing card, reader, doors and the Warden flow are unchanged and covered by the full regression. Criteria 7 and 8 (discovery of a larger operation; the payment trail progresses) need the decisions in section 4.

## Status after the compound build (2026-11-15)
Built in one pass for Milestones 7 to 10 (decisions in `OPENING_DECISIONS.md`): `scripts/world/opening_compound.gd` (`OpeningCompound`, hooked by one line in `outpost17.gd`), four quests (`opening_search`, `opening_research`, `opening_command_hall`, `opening_restricted`), and `tests/opening_compound_check.gd` (85 checks, 0 failed). Existing suites rerun on the change: dressing 47, world 61, world_progression 32, boss_intro 20, boss 20, patrol 24, patrol_retry 9, mission 50, quest 125, quest_chain 50, campaign_bot 34, campaign_flow 81, playthrough_bot 63, explosive_barrel 26, elite_strongholds 144, tactics_live 51, ai_scheduler 38, arena 49, run_tests 72, map 165, region 67, story_consistency 31, stage_* 32/53/40, boss_road 33, save 62, journal 85, ui_layout 56, opening_beach 27, boot 32: all 0 failed, 0 script errors.
Windowed screenshots were taken and looked at (guard station, annex window and door, dispatch hall with the hazard-striped command door); one sign hidden by a roof post was fixed. Nobody has played it by hand; frame rate in the capture (11 to 24 FPS) was measured in a software-rendered window under load and is not a budget figure.
Two small edits outside the new files: `tests/dressing_check.gd` skips interactables marked `behind_door` (the lab terminal and sheet are only reachable once the lab door is open; the new test proves reachability both ways), and `barrel_placement.gd` gained the gate-hall barrel (`op17_gate_hall`).
**This milestone (The Search):** a guard station in Area B's north-west corner (roof, bunks, a duty roster document, the Lab Pass keycard) and worker stores in Area C's storage room (bedrolls, a supply manifest). Interactions all change real state: the roster and manifest set their document flags, the pass sets `has_lab_pass` and opens the lab door. The cargo clue is in the dispatch terminal (Milestone 9). **Not built:** a separate "administrative office"; guards' dialogue beyond two captions. The existing corridor patrol (`PatrolC`) is the bypassable patrol; a second `PatrolGroup` was not added because the four-active-patroller cap would hold it back.
