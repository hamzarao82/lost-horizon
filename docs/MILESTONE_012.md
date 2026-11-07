# Milestone 012: Complete Game and Final Core Integration

Status date: 2026-11-07. **Nothing in this milestone is implemented yet.** This is the audit-based plan. Legend: **Implemented**, **Partial**, **Documented only**, **Verified** (a test or screenshot was run), **Not tested**, **Blocked**.

This is the last core milestone. It adds no features; it makes the existing game finishable. It stops after the release candidate and waits for approval; Milestone 13 (graphics) does not start automatically.

## 1. Scope decision: five regions, not three
The brief names Outpost 17, Research Complex and Iron Fortress. The project has **five** regions with a unlock chain already built (Outpost 17, Dead Coast, Blackwood, Research Complex, Iron Fortress). Recommendation: the campaign is the five-region chain; Dead Coast and Blackwood are not removed and are not skippable in the story, because the Research Complex unlock flag is set by Blackwood's mission 3. "Three major regions" in the brief is treated as the three acts' anchor locations, and every acceptance item applies to all five. This needs the owner's confirmation.

## 2. Dependencies (the state that decides how much of this milestone is possible)
| Milestone | State in `master` |
|---|---|
| 9 Iron Fortress, the Director, the ending trigger | region and boss agents were running; not merged; no ending sequence |
| 10 Campaign integration (journal, dialogue, campaign save, ending) | documents only |
| 11 Advanced combat and AI | documents only |
| 12 | this document |

Without 9 there is no final boss, no final mission and no ending, so the campaign cannot be completed and the brief's definition of done is **not reachable**. Milestone 10's ending and journal work, and Milestone 11's balance work, are partly prerequisites. If the owner wants to keep the 12-step order, Milestone 12 becomes an integration and audit pass over whatever 9 to 11 delivered, and the report must list what is missing instead of claiming completion.

## 3. Audit: what exists today
| Feature | State |
|---|---|
| New game, intro, first region | implemented, tested (`boot_check`, `screens_check`, playthrough bot) |
| Main menu | New Game, Continue (disabled without a save), Settings, Credits, Quit (hidden on web and mobile); **no "Load Game" list**: Continue loads the single save |
| Pause menu | Resume, Inventory, Character, Crafting, Map, Gear overview, Save, Load, Restart, Settings, Main menu, Quit |
| Settings | audio, quality preset, sensitivity, FPS toggle; gamepad bindings exist; **no key rebinding UI**, no display or resolution options beyond the window |
| Death and respawn | death screen, checkpoint respawn, tested through a real death reload |
| Campaign chain | unlock flags and a bridge quest from Outpost 17 to Dead Coast, Blackwood, Research Complex; the Iron Fortress link and the ending are not in `master` |
| Missions | first mission, three per region, four in the Research Complex, all event-driven and tested; **no mission failure handling** beyond player death and checkpoint reload; no timers |
| Save | version 4 with progression, inventory and per-region state, atomic writes with backup, migration from v2 and v3, hostile-data tests; real-save tests mid-region and mid-puzzle |
| Progression and economy | complete and tested; balance unjudged by a person |
| Combat, bosses | Warden, Subject Zero and the Commander exist and are fair by data; the Captain and the Director are in Milestone 9 |
| World | five region builders with physics route probes for Dead Coast and the Research Complex; Outpost 17 and Blackwood have connectivity checks; **no fall-detection or boundary tests for all regions** |
| Audio | procedural effects, ambience loops per region type, music loop; **no ending audio, no region-specific music, no boss music** |
| Platforms | Windows and Web export presets work (web exported many times); Android has a debug-signed APK from an earlier milestone and was **never run on a device**; web load takes 32 to 42 s with the menu visible after about 6 s; desktop frame rate at High quality is under 60 FPS on integrated graphics |

## 4. Known blockers and risks
- **No human has played the game** from the menu to anywhere beyond the first minutes. All end-to-end claims so far come from bots that fire quest events.
- The ending, final boss and campaign completion depend on Milestone 9.
- Mission failure handling and a "Load Game" list are missing as designed.
- Android: never run on a device; touch controls were built early and not retested after the RPG screens, map and journal were added.
- Cross-platform input: new screens (inventory, character, crafting, merchant, map) have layout tests at three sizes but no touch or controller testing on real hardware.
- Web: the saved game depends on browser storage (IndexedDB); persistence after a reload on web was probed once in an early build and is not covered by a test for the current build.
- Memory: the one detached-Outpost-17 design keeps its nodes allocated while the player is elsewhere.
- Many documents, quests and pickups were written by separate agents; duplicates and contradictions have not been reviewed by a person.

## 5. Plan
| Phase | Work | Status |
|---|---|---|
| 1 | Feature inventory generated from the project, not from documents: a script lists scenes, scripts, quests, regions, documents, pickups, tests, and checks every resource path loads (a "broken reference" test over `res://`) | not started |
| 2 | Fix integration holes: Research Complex to Iron Fortress link, campaign completion flag, ending trigger, any missing scene connections (depends on Milestones 9 and 10) | not started |
| 3 | Ending and credits flow reachable after the Director falls, with statistics, then main menu or free roam (Milestone 10 design) | not started |
| 4 | Mission audit: every mission has start, objectives, completion, rewards once, persistence, no soft lock after a save at any objective; add a generic failure rule where one applies (for example an escort-free design means failure is only death and checkpoint) | not started |
| 5 | World completion checks: fall-out-of-world recovery (a kill plane returns the player to the last checkpoint), boundaries and spawn points in all five regions, a navigation and trap check using the existing route probes | not started |
| 6 | Menus: a Load Game screen (one autosave, manual save, checkpoint save with time, region and level), Return to Main Menu confirmation, a controls reference, key rebinding if time allows | not started |
| 7 | Save audit at several campaign stages through the real `SaveManager`, with corrupt, missing and old-version cases; extend fixtures to every version | not started |
| 8 | Platform preparation: Windows export test; Web export plus a browser persistence test of the save (reload and continue); Android: export attempt, install and touch-control checks on a device (blocked until a device and signing are available) | blocked for the device part |
| 9 | Audio: ensure music and ambience stop and start correctly on region change, menu, death, ending; add ending and boss music placeholders (procedural) | not started |
| 10 | Full campaign tests: automated bot through all regions with saves and reloads (extends `campaign_bot_check`), plus a written manual playthrough checklist for a human, and the results recorded | automated part possible; manual part needs the owner |
| 11 | Bug-fix pass from the findings, release candidate documentation, export readiness table | not started |

## 6. Acceptance tracking
Every item in the brief's definition of done is **not started**. The brief's rule applies: the milestone is not complete because implementation stopped. Items that can only be judged by a person (feel, balance, readability, story quality) are listed as **manual** and stay unverified until one plays through. Items that need hardware or credentials (Android device, signing) are **blocked** and documented, not claimed.

## 7. Release-candidate checklist (to fill in at the end)
Project starts; main menu works; new game, continue and load work; all five regions accessible; campaign completable; save and load verified at several stages; credits work; no debug-only controls exposed; export presets present for Windows, Android and Web; the public repository rules still hold (no secrets or keystores, publish check passes); known limitations written into release notes. The v0.1.0 release and the Dependabot pull requests still need the owner's approval.

## 8. Things that belong to the next visual stage (Milestone 13)
Replace the boxy region art; real foliage, vehicles and buildings; character and weapon models and animations (a firing pose, aiming, new hit reactions); material and lighting passes; the washed-out Research Complex interiors; the Dead Coast and Blackwood look against the reference images; texture and memory budgets for Android and web; and the audio replacement by listened-to, licensed assets.

## 9. Status (2026-11-08)
Still a plan; no phase completed as a unit. **Fall recovery now exists** (Phase 5 item): a player who falls below y = -40 returns to the last solid ground with the fall speed cleared, or takes the normal death and checkpoint respawn when no ground is known; a region change or teleport forgets the old ground (`fall_recovery_check` 8). Merged work that feeds this milestone: all five regions reachable through real travel, the ending and credits flow, the journal, the arena state machine. **Still missing:** a Load Game list, key rebinding, mission failure rules beyond death, an ending replay from the menu, the Android device run, audio for the ending and bosses, the five open story contradictions, a full human play-through, and the web persistence check for the current build.
