# Milestone 9 (Opening series): The Command Center. Finding the truth behind Outpost 17

Status date: 2026-11-14. This is the brief, the inspection it asks for (done here from the real code), and a plan. **Nothing for this milestone is built.** It follows "The Research Wing" (`MILESTONE_RESEARCH_WING.md`, plan only). Legend: **Exists**, **Partial**, **Not built**, **Verified**, **Not tested**.

## 1. The central finding: the command center is the Warden's room
The brief wants the player to explore the command center, learn how the facility operates, take a payment clue, and leave with access to a restricted sector, **without starting the Warden encounter or triggering the arena**. In the real game that is not how Area D works:
- `outpost17.gd` `_build_boss_encounter()`: "The Warden waits in the command building: **the first entry into Area D runs his introduction**." A `BossIntro` node is added to the region, and entering Area D starts it.
- The command terminal is locked until the Warden falls (`requires_flag = boss_warden_defeated`, "Command terminal locked: the Warden holds the command room").
- The First Signal's own order puts "Enter the command center", "Defeat the command guards" and "Read the Project Black Site file" **before** "Defeat the Warden".
- The Warden fight is the fifth stage of the courtyard arena (waves 1 to 4, then the boss), and the boss is also registered for the HUD boss bar.

So the brief's "do not start the Warden encounter in this milestone" can only be met if the player does not enter Area D, or if `BossIntro` is deferred, or if the command center that this milestone uses is a different space. This needs a decision before anything is built (section 4).

## 2. Inspection report
| Piece | What exists |
|---|---|
| Geometry | Area D "Command Center" (z -62 to -92, 45 by 30 m): a command building with a 4 m front gap at x = 0, a back console, two desks, an east-yard patrol route (x = 18), and a **hidden back room** (north-west) screened by cover |
| Documents and terminals | `Project Black Site` (Area D, in front of the west desk: "live trials on the island, run under the Director. The Warden was the first subject to keep his mind. Outpost 17 exists to keep the trials quiet."), `Missing security log` (optional, hidden room: "They are not guarding the island. They are guarding what they put on it. The Warden answers only to the Director."), `Military record: Warden` (Area C: Sgt. Aldous Venn, declared killed in action, re-enrolled into Project Black Site as a Warden-class patient), the command terminal (locked until the Warden falls; pages: uplink open, relay your position) |
| Enemies | two command guards (a `PatrolGroup`, "PatrolD") walking the east yard; killing both sets `patrol_d_guards_cleared`; the Warden |
| Access items | `has_keycard` (the Warden carries the command keycard), `DoorCD` between C and D, the card reader at `DoorBC` |
| Mission wiring | `first_signal`: enter the command center, defeat the command guards, read the Project Black Site file, defeat the Warden, take the reward, contact the outside |
| Leadership references | **Already in the game's text:** the Director is named in the Black Site file and the missing log; Dead Coast and Blackwood and the Research Complex all refer to the Director (by title) and the Fortress ends with him as the final boss |
| Journal and objectives | journal entries exist per quest; the tracker, `tracker_first` pin and the objective pointer work in Area D |

### What is already revealed (so a "first major revelation" can overlap)
The Black Site file in Area D already tells the player the project's name, that it runs under the Director, that the Warden was a subject, and that the outpost's purpose is to keep it quiet. The brief wants an "intriguing but incomplete" first revelation and forbids explaining Black Site here. **The existing file would have to be the thing that is delayed, split or replaced**, or the new revelation would be a weaker repeat of it.

### Conflicts found
1. **Warden intro on entry** vs "do not trigger the arena prematurely" (section 1).
2. **The Director and Black Site are named inside the command center** already; the brief's "do not explain the entire operation yet" collides with the existing file, which is the strongest lore in the region.
3. **Warden foreshadowing already exists** (the record in Area C; the missing log "answers only to the Director"). The brief asks for subtle foreshadowing "if supported by existing lore"; it is supported, and most of it is already placed in Area C and the hidden room.
4. **The payment's movement into a restricted section** has no counterpart in Outpost 17: nothing in the map is a "restricted storage area" beyond the command building and its hidden room. The Dead Coast and Research Complex are different regions.
5. **"Security camera recording"**, "cargo log", "inventory entry", "guard communication": none of these document types exist; documents and terminals do.
6. **No leadership NPC** exists in Outpost 17 (the Director appears by title only), which fits the brief.

## 3. Mapping the brief to what exists
| Brief item | Status |
|---|---|
| Reach the existing command center | **Exists** (Area D through `DoorCD`) |
| More secure and important feel | **Partial.** Walls, console, desks and a hidden room; no monitoring props, no screens wall, no security station dressing |
| Security assignments, personnel records, access notices, worker transport records, internal communications, research references, operational logs | **Partial.** Only the Black Site file, the missing log and the command terminal exist; the rest is new short text |
| Short readable interactions | **Exists** (`LoreDocument`, `Terminal` pages) |
| Payment clue (camera recording, cargo log, guard talk, transport or inventory entry) | **Not built** |
| A meaningful security challenge (guarded terminal, restricted door, patrol, locked route, security control) | **Partial.** The command guards, `DoorCD`, the keycard flow and the Warden-locked terminal exist; a "security control interaction" is not authored |
| Larger operation foreshadowed, not explained | **Overlaps** the existing file (conflict 2) |
| Warden foreshadowing without revealing the encounter | **Mostly exists** already |
| Objective "Locate the restricted storage area." | **Not built**, and the level has no such place today |
| Ending: the information or access needed for the next sector | **Not built**; the existing continuation after the Warden is the Dead Coast road |
| Do not recover the payment; do not start the Warden | **Conflicts** with how Area D is wired (section 1) |

## 4. Decisions needed before building
1. **Order of the Warden and the command center.** Choose one: (a) **defer `BossIntro`** until a story flag (for example after the player takes the restricted-sector access) so the player can read and explore Area D first, keeping the Warden fight where it is; (b) **split Area D**: the front offices as the "command center" for this milestone and the back room and terminal as the Warden's space; (c) **leave the Warden intact** and make this milestone's command-center content the *approach* (Area C and the DoorCD hall) up to, not including, Area D.
2. **What happens to the existing Black Site file.** Keep it as the later, bigger revelation (read after the Warden or at the end), and write a smaller earlier discovery (an operations log mentioning "Section R", a "transfer to lower level", "unrecorded personnel") for this milestone.
3. **Where the next sector is.** Candidates already in the project: the hidden back room (a small restricted space), the Research Complex region, the Dead Coast road after the Warden. Naming it fixes the payment trail across Milestones 7 to 9.
4. **Whether the Outpost 17 enemies get tactics configs** for the command guards' fight (they are bare scenes today).

## 5. Planned work (assuming 4.1a and a new log as the discovery)
| Phase | Work | Status |
|---|---|---|
| 0 | Prerequisites: the opening plans through The Research Wing; decisions 4.1 to 4.3 | not started |
| 1 | Defer `BossIntro` behind a flag; a test that entering Area D does not start the Warden and that the old order (arena then boss) is unchanged for the old flow | not started |
| 2 | Dress Area D as an operations room (wall of monitor panels, roster board, a locked cabinet) from existing kit pieces | not started |
| 3 | Documents: an operational log, a security assignment sheet, a worker-transfer manifest, one that mentions an unusual security asset (the Warden) by role only, plus a cargo manifest that records "one unclaimed bag received, moved to the restricted store" | not started |
| 4 | Security challenge: the command guards patrol, a security console must be used to unlock the restricted door (a switch interaction with a real flag), and a reward behind it | not started |
| 5 | Revelation and objective: an earlier, smaller discovery; the objective "Locate the restricted storage area." added to the quest chain and persisted | not started |
| 6 | Tests: Area D entry does not fire the intro early; every interaction sets real state; route probes; saves at each step; regression of `first_signal`, `boss_intro_check`, `boss_check`, the arena suites | not started |
| 7 | Windows and browser checks, performance, report | not started |

## 6. Risks and honest limits
- The Warden's introduction and the command terminal's lock are baked into Area D; deferring them touches the boss flow and its tests (`boss_intro_check`, `boss_check`, the `first_signal` order in `mission_check` and `campaign_bot_check`).
- The existing Black Site file already names the Director and the project, so any "first" revelation risks being a weaker copy unless the file is moved.
- The opening milestones before this one are unbuilt or untested in play.
- There is no restricted-storage place in Outpost 17 today; naming one is a story decision.
- Pacing, difficulty and the quality of the revelation need a person.

## 7. Acceptance tracking
All twelve criteria in the brief are **not started**. Criterion 10 (Warden encounter and existing missions intact) holds today because nothing is changed and the full regression passes; it is the criterion most at risk once building starts. Criterion 8 (Warden foreshadowed only where supported) is already satisfied by existing text in Area C and the hidden room.
