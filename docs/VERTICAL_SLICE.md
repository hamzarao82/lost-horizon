# Vertical Slice Definition

Tags are explained in [MILESTONE_004.md](MILESTONE_004.md).

## 1. Goal
One complete, polished, 20–30 minute experience: **Outpost 17 and the mission "The First Signal"**. It must show the quality bar of the finished game, not its full content.

## 2. Player journey (the 14 steps of the brief)

| # | Step | Current support | Gap for Milestone 004 |
|---|---|---|---|
| 1 | Start the game | `[IMPLEMENTED]` loading screen then game (`master`); **no main menu** | `[NEW-M4]` main menu (new game / continue / settings) |
| 2 | Enter the world | `[IMPLEMENTED]` spawn on the beach (`master`) | none |
| 3 | Understand the premise | `[IMPLEMENTED]` skippable 20–30 s caption intro and radio lines (`master`) | `[NEW-M4]` polish and radio design (see STORY_AND_MISSION_FLOW.md) |
| 4 | Explore Outpost 17 | `[IMPLEMENTED]` four areas, doors, dressing (`milestone-003`), greybox look | `[NEW-M4]` merge with 002 art; command-center content |
| 5 | Discover objectives | `[IMPLEMENTED]` tracker, objective pointer, banners (`milestone-003`) | tune clarity (see QA) |
| 6 | Fight regular enemies | `[IMPLEMENTED]` three enemy types, waves, patrols (`milestone-003`) | combat polish, command-center elites |
| 7 | Collect loot | `[IMPLEMENTED]` drops, crates, caches, pickups | loot feedback and comparison UI |
| 8 | Upgrade equipment | `[IMPLEMENTED]` eight weapons, armor bar, plates, auto-equip | equipment screen, comparison, rarity presentation |
| 9 | Solve environmental puzzles | `[IMPLEMENTED]` ordered power puzzle (`milestone-003`), verified by the playthrough bot | clearer in-world feedback is `[PROPOSED]` |
| 10 | Progress the main quest | `[IMPLEMENTED]` 9 objectives plus one optional (`milestone-003`) | acts 4–6 objectives (see story doc) |
| 11 | Encounter and defeat the Warden | `[IMPLEMENTED]` Area D encounter and the wave-5 fight | complete encounter redesign (see boss doc) |
| 12 | Receive completion rewards | `[IMPLEMENTED]` quest reward items, Warden drops | `[NEW-M4]` mission results screen |
| 13 | Save progress | `[IMPLEMENTED]` save v2, checkpoints, autosave per wave (`milestone-003`) | reliability pass, results persistence |
| 14 | Reload and continue | `[IMPLEMENTED]` pause-menu Load, respawn at checkpoint | `[NEW-M4]` "Continue" on the main menu |

## 3. Content inventory of the slice

| Content | Target | Status |
|---|---|---|
| Regions | 1 (Outpost 17: areas A–D plus the courtyard arena) | `[IMPLEMENTED]` greybox on `milestone-003` |
| Main mission | The First Signal, acts 1–6 | acts 1–3 `[IMPLEMENTED]`, acts 4–6 `[NEW-M4]` |
| Enemy types | 3 regular (Soldier, Heavy, Hunter) + Warden | `[IMPLEMENTED]` |
| Patrol squads | 2–3 (currently 1) | `[NEW-M4]` more squads, including command center |
| Weapons / armors | 8 / 4 plus armor plate | `[IMPLEMENTED]` |
| Puzzle | 1 (power sequence) | `[IMPLEMENTED]` |
| Boss | 1 (Warden) | baseline `[IMPLEMENTED]`, full design `[NEW-M4]` |
| Characters and weapons art | rigged characters, 8 weapon models | `[IMPLEMENTED]` on `milestone-002` only |
| Audio | SFX, ambience, music, radio | partly `[IMPLEMENTED]` (14 procedural sounds + loop); see audio doc |
| Screens | main menu, pause, settings, HUD, inventory, equipment, results, death | pause, settings, HUD `[IMPLEMENTED]`; others `[NEW-M4]` |

## 4. Slice length and pacing target (`[PROPOSED]`, to be measured)
Opening and beach 3–4 min · compound combat and card 5–6 min · research wing and puzzle 5–6 min · command center 4–5 min · Warden 3–6 min · results 1 min. Total about 20–28 minutes for a first playthrough. The playthrough bot measures logic, not human time; pacing must be timed by a person.

## 5. Definition of done
The slice is done when all of the following are true and recorded in QA_AND_ACCEPTANCE_TESTS.md:
1. A new player can go from the main menu to the mission results screen without outside help.
2. Every objective can be completed in the real build (not only by a bot), in the intended order and in the allowed out-of-order cases.
3. Combat feels responsive by the measurable criteria in the combat section of QA (input-to-swing latency, hit feedback within one frame of impact).
4. The Warden fight is winnable without exploits, has two clear phases, and its telegraphs are readable on the new character model.
5. Save, quit, reload and continue restore position, equipment, quest and world state.
6. Dying never soft-locks the mission.
7. The existing five-wave arena still completes (regression).
8. Windows 60 FPS target, Android 30 and web 30 are **measured** on real devices and results are recorded (a missed target is documented, not hidden).
9. No known crash or blocker; all known limitations are listed in RELEASE_READINESS.md.

## 6. Prerequisites
- Milestones 002 and 003 merged into one branch with all suites passing (currently 891 and 981 checks on separate branches).
- v0.1.0 of `master` released so the starting point is public and recoverable.

## 7. Out of scope
Everything in section 16 of the brief: further regions, multiplayer, accounts, backend, open-world streaming, crafting, large dialogue trees, extra bosses, procedural generation.
