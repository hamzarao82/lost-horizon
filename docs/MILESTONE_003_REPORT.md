# Milestone 3 report: Outpost 17, quests, interaction, puzzle, patrols, save v2, Warden encounter

Branch `milestone-003` (worktree `lost-horizon-m3`), measured on an Intel UHD 620 laptop. Nothing here was run on web or Android.

## What was built, per step
| Step | Built | Evidence |
|---|---|---|
| 1 World foundation | Areas C (Research Access Facility) and D (Command Center) north of the courtyard, doors, boundaries, area triggers with names. The beach (A) and the courtyard (B) are unchanged. | `world_check` (61) |
| 2 Exploration | Props for all four areas, two hidden caches, 13 listed colliders, storytelling props | `dressing_check` (30, includes a physics reachability flood fill) |
| 3 Interaction | Door, CardReader, SecurityPanel, Terminal, Checkpoint, LoreDocument, PowerSwitch on the existing Interactable/Interactor | `door_check` (12), `interact_check` (84) |
| 4 Quests | 9-objective First Signal chain, optional missing-log objective, quest items | `quest_chain_check` (48), `quest_check` (125) |
| 5 Puzzle | Ordered power puzzle (B, A, C) with a panel-first rule, reset on a wrong order | `puzzle_check` (27) |
| 6 Patrols | PATROL / SUSPICIOUS / SEARCH / RETURN states, sight cone + line of sight, noise, stuck recovery, 4-patroller cap, one squad | `patrol_check` (24) |
| 7 Warden | Area D encounter with the same Warden scene: sealed door, 3 s introduction, flags, unseal on victory | `boss_intro_check` (20), `boss_check` (20) |
| 8 Save v2 | Version 2, checkpoint snapshot, respawn at the last checkpoint outside the arena waves | `save_v2_check` (31, includes a real death and scene reload) |
| 9 UI | Location banner, optional-objective line, mission-complete banner (earlier), **objective pointer** (this step) | `ui_layout_check` (46), playthrough bot pointer checks, 2 screenshots |
| 10 Regression | Full-quest playthrough bot, all suites, benchmark | see below |

## Objective pointer (step 9)
`scripts/ui/objective_pointer.gd`, added by `Hud` as a child on its own layer. It finds the current objective with the same rule as the tracker, resolves where it is from the live scene (interactables by id, the real area trigger, the next puzzle switch, the access-card pickup, the nearest living enemy), and draws a compass arrow with a label and distance ("Perimeter 26 m"). It hides when the target is on screen and closer than 6 m. Placement is a pure function that slides the arrow toward the middle until it clears the HUD bands and the touch buttons; the bot checks all 24 directions at 1280x720 and 1600x720 for mouse and touch.

## Playthrough bot (`tests/playthrough_bot.gd`, about 5 s)
It drives "The First Signal" with real events: the player body is moved into the area triggers and onto the card pickup, `Interactable.interact()` is called as the Interactor does, enemies are killed through `receive_hit`. Result: **41 checks, 1 failed**.
- PASS: area A entry, checkpoint desk, radio, courtyard wake-up (squad and guards), 4 kills, access card drop and pickup (quest item), card reader and door B-C, area C entry, panel inspection, wrong-order reset, B-A-C solve, Warden encounter (exactly one Warden), optional missing log, military terminal, quest completed once, reward once, access card kept, optional objective recorded, checkpoint save and load keeps the completion.
- **Was a real game bug, now fixed:** nothing in the game created the `SequencePuzzle` node, so the switches turned on in any order and objectives 6, 7 and 9 could not complete. Fixed by `Outpost17` building the puzzle from the start and `PowerSwitch` creating it if missing. The bot no longer uses a workaround and now passes this check.

## Acceptance criteria
| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Outpost 17 is a playable explorable region | Partly | Four connected areas, greybox look; `world_check`, `dressing_check` |
| 2 | The arena remains accessible | Met | `run_tests`, `boss_check`, waves unchanged |
| 3 | Movement and combat still work | Met | `input_check`, `lockon_check`, `run_tests` |
| 4 | Enemies patrol and engage | Partly | `patrol_check`; one squad, direct steering, no baked navigation |
| 5 | Interactable objects work | Met | `interact_check`, `door_check` |
| 6 | Doors and terminals work | Met | `door_check`, bot (door B-C, terminal) |
| 7 | One main quest completes start to finish | **Met** | `playthrough_bot` plays the whole chain with real events (41 checks) |
| 8 | The power puzzle works | **Met** | `puzzle_check` (27) and the bot: panel first, order B, A, C, wrong order resets |
| 9 | Loot is found by exploring | Met | `dressing_check` (caches), crates, `equipment_check` |
| 10 | The Warden connects to progression | Met | `boss_intro_check` |
| 11 | Objectives update correctly | Met | `quest_chain_check`, bot steps 1-7 |
| 12 | HUD shows mission information | Met | tracker, optional line, banners, pointer; `ui_layout_check` |
| 13 | Checkpoint and save/load work | Met | `save_v2_check`, bot |
| 14 | Equipment and inventory intact | Met | `equipment_check`, `save_check` |
| 15 | No major performance regression | Met | benchmark below |

## Known limits
- Greybox look: primitive walls and props; the characters are the placeholder boxes on this branch.
- Patrols use direct steering with stuck recovery, not baked navigation meshes; only one squad (research wing) exists, Area D has none.
- The Warden is the Milestone 1 boss with its existing attack patterns (phases unchanged); the encounter only adds the introduction, the seal and flags.
- Web and Android were not tested with the new areas.
- The introduction caption of the Warden waits 2.7 s so it does not overlap the location banner.
- Headless text metrics are unreliable: two layout checks (`quest_check`, `fx_check` dust puff) are occasionally flaky under heavy CPU load and pass when re-run.

## Performance (windowed `tests/benchmark.gd`, four enemies, 20 s, Intel UHD 620, vsync off)
| Branch | Avg FPS | 1% low | Draw calls (peak) |
|---|---:|---:|---:|
| master (same day, same machine) | 93-99 | 47-49 | 177-181 |
| milestone-003 before this step | 96 | 38-41 | 150-156 |
| milestone-003 now (with pointer) | 100 | 51-53 | 156 |
The other agents or tests were using the machine during some of these runs, so differences of a few FPS are noise.
