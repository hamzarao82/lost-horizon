# Story and Mission Flow

Tags are explained in [MILESTONE_004.md](MILESTONE_004.md). Existing quest mechanics are described in `QUESTS.md` and `STORY.md`; this document defines the complete mission as the player experiences it.

## 1. Premise
A survivor wakes on a beach among wreckage after a transport incident, with no memory of the crash, no weapon worth the name and no way to call for help. A military radio transmission leads to Outpost 17, a restricted installation. Inside, records and sealed laboratories show that the island hosts illegal experiments ("Project Black Site") run by a secret organisation, and that the outpost commander, the Warden, answers to someone called the Director.

## 2. Story delivery (no expensive cutscenes)
| Method | Use | Status |
|---|---|---|
| Caption intro over black and a slow camera push | the first 20–30 seconds (storm, wreck, wake up) | `[IMPLEMENTED]` on `master` (skippable) |
| Radio transmissions (text captions with a short static sound) | guide the player, carry the voice of the unseen contact | `[IMPLEMENTED]` basic radio lines; `[NEW-M4]` full design below |
| Lore documents and security logs | explain the island at the player's pace | `[IMPLEMENTED]` mechanism (`LoreDocument`); `[NEW-M4]` final texts |
| Environmental storytelling | props, scorch marks, abandoned vehicles, signs | `[IMPLEMENTED]` greybox props on `milestone-003`; art pass `[NEW-M4]` |
| Terminals | short text pages | `[IMPLEMENTED]` |
| Boss introduction | camera look-at plus one line | `[IMPLEMENTED]` (3 s, `milestone-003`) |

Rules: every text screen is skippable, no line is longer than two subtitle lines, and nothing blocks play for more than 5 seconds except the opening.

## 3. Opening sequence (target 25 seconds)
1. Black screen, storm sound, caption: "The transport went down in the storm." (2.5 s)
2. Caption: "You wake on a beach. You remember nothing." (2.5 s)
3. Camera rises from the sand to the wreckage; player control returns. Title card "LOST HORIZON: BLACK SITE" fades. (4 s)
4. First objective appears: **Find a way to call for help.**
5. After 10 s of play, a static burst and the **first transmission** (see section 5) points toward the radio hut.

## 4. The mission "The First Signal" — six acts

Existing objective ids are from `resources/quests/first_signal.tres`. New objectives are `[NEW-M4]` and must be implemented through the same event-driven quest system.

| Act | Player goal | Objectives (E = existing, N = new) | Completion condition | Notes |
|---|---|---|---|---|
| **1 Arrival** | Understand the island, reach the outpost | E: Reach the outer perimeter (area A entered). N: **Find the emergency radio** (move the existing radio objective earlier) | area trigger, radio used | beach tutorial: movement, camera, a medkit crate |
| **2 Investigation** | Investigate and arm up | E: Investigate the abandoned checkpoint; E: find the transmission source; E: eliminate hostile soldiers (4 kills); E: locate the security access card. N: **read one military record** (any lore document) | desk read, radio used, 4 kills, card flag | first patrol contact; teaches stealth, noise and combat |
| **3 Facility access** | Open the research wing | E: restore power (panel first, switches B, A, C); E: access the military terminal; E: discover the restricted research facility; E: unlock the next location flag | puzzle solved, terminal read, area C entered | the clue lives in the security log |
| **4 Military command** | Reach the command center and learn about Project Black Site | N: **Enter the command center** (area D); N: **Defeat the command guards** (kill count in area D, elites); N: **Read the Project Black Site file** (document `log_project_black_site`) | area entered, guards dead, file read | optional: find the missing security log (existing) |
| **5 Boss** | Defeat the Warden | N: **Defeat the Warden** (boss defeated flag); N: **Take the Warden's signature reward** (cleaver or plate picked up) | flag `boss_warden_defeated` and item collected | the Area D encounter, or the wave-5 fight if already won |
| **6 Completion** | Finish and save | N: **Contact the outside** (use the command terminal after the Warden falls) → quest complete; mission results; autosave; next location unlocked | terminal used after the boss | results screen, see section 6 |

Out-of-order handling: the existing quest manager remembers early events, so objectives can complete when their event already happened. Acts are a guidance structure, not locks; the only hard gates are the card reader (needs the card) and the terminal (needs power).

### Objective transitions
The tracker shows one current main objective and, when relevant, one optional line. On completing an objective: a short chime, the tracker text updates, and the objective pointer retargets. On completing an act: a "mission update" banner with the act name (`[NEW-M4]`, uses the existing banner band).

## 5. Radio transmissions (original text, `[NEW-M4]` unless noted)
Speaker: an unseen contact ("Static"), calm, short sentences. Each is shown as a subtitle with a static sound; no voice recording is required. Maximum two lines each.

| # | Trigger | Text |
|---|---|---|
| R1 | 10 s after the opening | "…anyone on this channel… the old relay at Outpost 17 is still alive. Follow the signal." |
| R2 | radio used | "You made it. Listen: the gate is dead. Three breakers, spread around the beach. Wake them." |
| R3 | `[IMPLEMENTED]` style | gate opened: "Power's back. Careful in the compound, they patrol." |
| R4 | access card found | "That card opens the research wing. Whatever they're hiding is behind it." |
| R5 | terminal read | "Coordinates received. Now the command center. The Warden holds it." |
| R6 | boss introduction | (the Warden) "This is as far as you go." |
| R7 | mission complete | "Signal confirmed. They know you're alive now. Move." |

Existing radio lines on `master` (`world_flow.gd`, `RADIO_LINES`) are `[IMPLEMENTED]` and should be reviewed and merged with this table rather than duplicated.

## 6. Mission completion and results (`[NEW-M4]`)
Shown after objective 6 completes. Content: mission title and "COMPLETE", time taken, enemies defeated, secrets found (documents and caches of total), the reward received (item name and rarity colour), the checkpoint reached, and a button: **Continue** (stay in the world) or **Main menu**. The game autosaves on this screen and shows "Progress saved". It also sets the "next location unlocked" flag (already `[IMPLEMENTED]`); the next region itself is out of scope, so the Continue state ends with a short "To be continued" line.

## 7. Connection to the existing quest line
- `first_signal` (9 objectives + 1 optional) `[IMPLEMENTED]` on `milestone-003` is extended, not replaced.
- Arena quests `broken_perimeter` (clear five waves) and `final_transmission` `[IMPLEMENTED]` remain as optional **arena challenges** reachable through the courtyard; they must not conflict with the new Act 5 flags (`boss_warden_defeated` is shared by design).
- The old M1 ending sequence `[IMPLEMENTED]` (`Ending.tscn`) is reused for the credits shown after "To be continued" if desired.

## 8. Unverified
- Nobody has measured how long the six acts take a human; the 20–30 minute target is an estimate.
- The wording above is a draft for approval.

## 9. Implementation status (Milestone 4, mission agent)
Acts 4–6 of section 4 are `[IMPLEMENTED]` on `milestone-004` as objectives 10–15 of `first_signal` (see `docs/QUESTS.md`), including R4, R5 and R7 subtitles and the `mission_completed` signal for the results screen. Not done: moving the radio objective earlier (Act 1), the extra "read one military record" objective of Act 2, R1 timing, mission-update banners per act. Verified by headless tests only; nothing here was played by a human.

## Status: optional military record
`log_military_record` is an optional lore document in Area C (west side, x -17, z -52): the service record of the soldier who became the Warden. It is not a quest objective, so the required objective count is unchanged.
