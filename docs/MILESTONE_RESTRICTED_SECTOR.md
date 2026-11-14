# Milestone 10 (Opening series): The Restricted Sector. The road to the Warden

Status date: 2026-11-14. This is the brief, the inspection it asks for (done here from the real code), and a plan. **Nothing for this milestone is built.** It follows "The Command Center" (`MILESTONE_COMMAND_CENTER.md`, plan only). Legend: **Exists**, **Partial**, **Not built**, **Verified**, **Not tested**.

## 1. The central finding: there is no separate restricted sector, and the order is reversed
The brief puts the milestones in the order *Search → Research Wing → Command Center → Restricted Sector → Warden*, ending the restricted sector "at the entrance to the existing Warden encounter". The real map of Outpost 17 is shorter and runs in a different order:

| Real area (from `outpost17.gd`, `boss_intro.gd`) | z range | Role today | Brief's name for it |
|---|---|---|---|
| A, Outer Perimeter | 30 to 80 | beach strip, abandoned checkpoint | the perimeter (Milestone 5) |
| B, Military Compound | -30 to 30 | fenced courtyard, the five-wave arena (the Warden is also **wave 5**), the quartermaster, the card reader on `DoorBC` | the compound (Milestones 6 and 7) |
| C, Research Access Facility | -62 to -30 | storage room, control room, generator shed, the military terminal, a patrol; ends at `DoorCD` | the research wing (Milestone 8) |
| D, Command Center | -92 to -62 | the command building, its desks and terminals, a hidden back room, the "Project Black Site" file, **and the Warden's boss room** | the command center (Milestone 9) |

- **The Warden fights in Area D.** `BossIntro` ("The Warden encounter in Area D (Command Center)") spawns him at the centre of the command building (0, 0.1, -75), runs an introduction on the first entry, and **seals the doorway at z = -62.6** behind the player with a collider until the fight ends. The same Warden also appears as wave 5 of the courtyard arena (Arena Mode keeps that).
- **So "the entrance to the Warden encounter" is `DoorCD` at the end of Area C**, and "the road to the Warden" is Area C. There is no restricted sector between the command center and the boss: the command center *is* the boss room (see Milestone 9).
- Milestones 7, 8, 9 and 10 therefore all describe the same two areas of about 45 by 30 m each (C and D), plus a few rooms in B. A real build must decide which beats go where, not stack four new sections.

## 2. Inspection report
| Piece | What exists |
|---|---|
| Restricted-sector scenes | none as such. The nearest are Area C's control room and generator shed, the `DoorBC` and `DoorCD` doors, and Area D's hidden back room (north-west, behind cover) |
| Access-controlled doors | `DoorBC` (card reader, "Door locked: access card required"), `DoorCD` (opened by the ordered breaker puzzle B, A, C or the power flow, plus the first mission's steps), `Door.lock_reason` text |
| Security systems | `CardReader`, `Keycard`, `SecurityPanel`, `PowerSwitch`/`BreakerSwitch`/`SequencePuzzle`, the command guards' `PatrolGroup` |
| The Warden entrance | `DoorCD` (z -62). When the player steps into Area D, `BossIntro` shows the introduction, spawns the Warden, seals the door. The player cannot leave until he dies (or the player does) |
| Warden scripts | `scripts/ai/warden.gd`: two phases, slam, charge, leap, fire lines, flurry, shockwave, defeat sequence; attack data now retuned for the telegraph rule (see `MILESTONE_011.md`); loot table `warden_loot.tres`; flags `warden_intro_done`, `boss_warden_defeated`, `warden_d_defeated` |
| Enemy types and encounters | soldier, heavy, elite hunter (patrol in C: soldier plus elite hunter on a corridor route; two command guards in D). Tactics configs are **not** applied to these bare Outpost 17 scenes |
| Payment references | none |
| Checkpoints | `Checkpoint` interactables: the beach-gate checkpoint (A) and `checkpoint_b` in B. **There is no checkpoint in Area C or just before `DoorCD`**, so the last save point before the boss is back in the courtyard |
| Mission dependencies | `first_signal` order: ... restore comms power, access the terminal, discover the research facility, unlock the next location, enter the command center, defeat the command guards, read the Black Site file, defeat the Warden, take the reward, contact the outside. `boss_warden_defeated` also feeds `CampaignFlow` (the road to the Dead Coast opens when the Warden and the second boss are down) |

### Conflicts found
1. **Reversed order / no separate sector** (section 1).
2. **"Do not trigger the boss prematurely"** has a real mechanism problem: the seal closes the moment the player enters Area D, so an Area D "road" cannot be explored with a free return.
3. **"Prepare for the boss"** (healing, loot, checkpoint) has no checkpoint and no obvious pre-boss room before `DoorCD` today.
4. **The Warden's story is already placed**: the record in Area C (Sgt. Aldous Venn, a decorated soldier declared killed in action and re-enrolled as a "Warden-class patient"), the missing log in Area D ("The Warden answers only to the Director"). The brief's foreshadowing is supported and mostly already there.
5. **The payment trail** has no endpoint in the map (see Milestones 7 to 9).
6. **Two Warden fights** exist (Area D and arena wave 5). The brief assumes one encounter; flags already treat either as "the Warden defeated".

## 3. Mapping the brief to what exists
| Brief item | Status |
|---|---|
| Enter the restricted sector using the earlier information or access | **Partial.** The card and the breaker puzzle already gate `DoorBC` and `DoorCD`; a new "restricted" lock would be one more existing door type |
| More secure, more dangerous look | **Partial.** Area C can be re-dressed; the kit has hazard stripes, pipes and a generator shed; nothing marks a "high security" zone |
| Stronger, progressively harder encounters using existing enemies | **Partial.** The elite hunter and heavy exist; a guarded checkpoint at `DoorCD` and a confined fight in the corridor between storage and control rooms are possible; **no config applies the tactics here** |
| Environmental discoveries: warnings, security instructions, earlier incidents, restrictions around a specific individual | **Partial.** The Warden record and the missing log exist; the rest would be new short documents and signage |
| Payment trail: a stronger indication it went deeper | **Not built**; no destination |
| Warden foreshadowing: warning, damaged room, earlier confrontation, locked arena entrance | **Partial.** A damaged room is easy (props and decals in Area C or the hidden room); the locked entrance is `DoorCD` itself; the record and log exist |
| Pre-boss preparation: healing, loot, equipment, checkpoint, no unlimited resources | **Partial.** Crates and loot tables exist; **a checkpoint before `DoorCD` does not**; a place to buy or stock is the quartermaster in Area B |
| End at the boss entrance with a clear objective, without auto-starting the fight | **Partial.** The natural end point is standing at `DoorCD`; the existing flow starts the intro only when the player steps through |
| Prevent access to later regions | **Exists** (the unlock chain) |

## 4. Decisions needed before building
1. **Merge the four milestones' geography.** Recommended mapping: Milestone 7 = Area B's side rooms and Area C's storage room; Milestone 8 = Area C's laboratory dressing; Milestone 9 = Area C's control room and the `DoorCD` hall as the "command" approach (with the Area D interior left for the Warden); Milestone 10 = the corridor and gate at `DoorCD`. This keeps Area D as the boss room and avoids stacking four new sections.
2. **Where the Black Site file lives.** Same question as Milestone 9: it is inside the boss room today.
3. **A checkpoint and a supply cache just before `DoorCD`.** Needed for "prepare for the boss"; small and uses existing components.
4. **Whether the Outpost 17 enemies get tactics configs.**

## 5. Planned work (with decision 4.1 as recommended)
| Phase | Work | Status |
|---|---|---|
| 0 | Prerequisites: the opening plans through The Command Center; decisions 4.1 to 4.4 | not started |
| 1 | A guarded checkpoint at the `DoorCD` hall: a patrol of two to three (elite hunter plus soldiers), an open fight space with cover (crates, barriers), a corridor choke, optionally barrels | not started |
| 2 | Warnings and foreshadowing props: hazard signage, a damaged cell or room with a note, the Warden record moved or repeated as a security notice about "Section W" access | not started |
| 3 | Pre-boss preparation: a checkpoint, one supply crate with a medkit and armor plate, a quartermaster mention; a test that the player can reach the boss with a reasonable kit | not started |
| 4 | Payment clue and objective: a cargo record that the bag was routed toward the command level, objective text persisted | not started |
| 5 | Tests: no early seal or intro; `DoorCD` opens through the existing flow; the checkpoint saves and restores the player correctly; regression of `boss_intro_check`, `boss_check`, `mission_check`, `campaign_bot_check`, arena suites | not started |
| 6 | Windows and browser checks, performance, report | not started |

## 6. Risks and honest limits
- The brief and the map disagree about the structure; building as written would invent a restricted sector and duplicate Area C and D, which the brief itself forbids.
- The seal behind the player in Area D and the two-Warden structure are real constraints on any "approach" design.
- No checkpoint exists near the boss; a bad pre-boss kit has no safety net today.
- The balance of the Warden fight itself has never been played by a person.
- Opening milestones 1 to 9 are unbuilt or unplayed, so this one has no tested starting state.
- Pacing and difficulty need a person.

## 7. Acceptance tracking
All twelve criteria in the brief are **not started**. Criteria 10 (the Warden encounter intact) and 11 (save/load and progression) hold today by the full regression. Criterion 9 ("a clear boss-entry point") is satisfied today by `DoorCD` and `BossIntro`, but nothing marks it to the player.
