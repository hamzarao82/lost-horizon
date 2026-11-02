# QA and Acceptance Tests

Tags are explained in [MILESTONE_004.md](MILESTONE_004.md). Rule: **a feature is reported as working only when a test below was actually run and its result recorded.** Automated checks prove logic in headless mode; they do not prove feel, visuals, audio or device behaviour.

## 1. Existing automated suites `[IMPLEMENTED]` (headless Godot, `godot --headless --path . -s tests/<name>.gd`)
Counts are from the `milestone-003` branch at commit `ccab2bc` (all passing when last run); `milestone-002` and `master` have fewer suites.

| Area | Suites (checks) |
|---|---|
| Core combat, AI, waves, loot | `run_tests` (72), `boss_check` (20), `lockon_check` (25), `input_check` (51), `hitstop_check` (13) |
| Equipment, teleport, effects | `equipment_check` (61), `teleport_check` (51), `fx_check` (28) |
| Save, boot, settings | `save_check` (62), `save_v2_check` (31), `boot_check` (32), `menu_check` (17) |
| World, quests, puzzle | `quest_check` (125), `quest_chain_check` (48), `puzzle_check` (27), `interact_check` (84), `door_check` (12), `world_check` (61), `dressing_check` (30) |
| AI and boss encounter | `patrol_check` (24), `boss_intro_check` (20) |
| UI | `ui_layout_check` (46) |
| Whole-quest regression | `playthrough_bot` (41): plays The First Signal with real game events |
| Milestone 002 only | `anim_sync_check` (122), `env_kit_check` (42), `verify_weapons` (106), `verify_glb` |

Known flakes: `fx_check` "dodging kicks up a dust puff" and layout checks failed occasionally under heavy CPU load and passed on re-run; each failure must be re-run and recorded, not ignored.

## 2. Test cases for the vertical slice
Type: **A** automated, **M** manual, **D** device. Status column is filled during Milestone 004 QA; empty here means not yet run.

| ID | Area | Test | Pass criterion | Type | Existing coverage |
|---|---|---|---|---|---|
| QA-01 | New game | Main menu → New Game → intro → control returns | no error, intro skippable, objective shown | M | partly (`boot_check`, intro on master) |
| QA-02 | Movement | walk, run, sprint, jump on slopes, boxes, doors | no jitter, no stuck on door frames | M + A | `input_check` |
| QA-03 | Camera | rotate, collide with walls and interiors, lock-on | camera never clips into walls in areas A–D | M | `lockon_check` (logic) |
| QA-04 | Combat | light x3, heavy, sprint/air/spin attacks, dodge, buffering | frame data matches `COMBAT.md`; hits only in active frames | A | `run_tests`, `input_check` |
| QA-05 | Combat feel | input-to-swing latency; hit feedback on the impact frame | swing starts the same physics tick as the press; measured by script | A | `input_check` |
| QA-06 | Enemy AI | notice, chase, attack, stagger, die; token limit | per `patrol_check`/`run_tests` | A | yes |
| QA-07 | Patrols | route walking, suspicion, search, return, never stuck | per `patrol_check` | A + M | yes (one squad) |
| QA-08 | Boss phases | phase change at the chosen threshold, new attacks, defeat | frame-data table and phase test | A | baseline in `boss_check` |
| QA-09 | Loot | drops, crates, caches, pickups once | per `run_tests`, `dressing_check` | A | yes |
| QA-10 | Equipment | equip better, ignore worse, armor refill, plates | per `equipment_check` | A | yes |
| QA-11 | Armor maths | damage drains armor then health; report full damage | per `equipment_check` | A | yes |
| QA-12 | Medkits | heal, no waste at full health, buffer 0.8 s | per `run_tests`/`input_check` | A | yes |
| QA-13 | Teleport | charges, recharge, safe destination, persistence | per `teleport_check` | A | yes |
| QA-14 | Quest progression | all 9 objectives, optional, out of order, reward once | per `quest_chain_check`, `playthrough_bot` | A | yes |
| QA-15 | Interaction | prompts, one press = one interaction, touch Use button | per `interact_check` | A + D | partly |
| QA-16 | Puzzle | panel first, order B, A, C, wrong order resets | per `puzzle_check`, bot | A | yes |
| QA-17 | Checkpoints | activate, save, respawn there | per `save_v2_check` | A | yes |
| QA-18 | Save/load | quit and reload restores position, gear, quests, flags | per `save_v2_check`, bot | A + M | yes (headless) |
| QA-19 | Corruption | damaged save → backup/clean fallback, never overwrite valid | per `save_check` | A | yes |
| QA-20 | Death/respawn | die in each area and during waves; no soft lock | per `save_v2_check` + manual loop | A + M | partly |
| QA-21 | Mission completion | results screen, autosave, next-location flag | new test | A + M | `[NEW-M4]` |
| QA-22 | Scene transitions | boot → game; reload after death; menu → game | no leaked state, no errors | A | `boot_check` |
| QA-23 | UI scaling | 1280x720, 1600x720, 360x800; touch mode | no overlaps, all info present | A + M | `ui_layout_check` |
| QA-24 | Performance | per PERFORMANCE_BUDGET.md | meets or documents misses | A + D | benchmark scripts |
| QA-25 | Arena regression | five waves complete, Warden at wave 5, loot | existing arena results unchanged | A | `run_tests`, `boss_check` |
| QA-26 | Audio | every event plays, no clipping, music ducks | listening checklist | M | `[NEW-M4]` |
| QA-27 | Controller | full play on a gamepad | no unbound action in menus or play | D | not implemented (gap) |
| QA-28 | Android | install, play 10 minutes, touch controls, backgrounding | no crash, 30 FPS target recorded | D | not run |
| QA-29 | Web | load time, first click, save persistence after reload | per `WEB_QA.md` | A + M | partly (`master`) |

## 3. Combat quality measurements (how "feels good" is defined)
| Metric | Target | Method |
|---|---|---|
| Input to attack start | same physics tick (≤ 16.7 ms at 60 Hz) | `input_check` timing assertion |
| Light attack total time | within the table in `COMBAT.md` ±1 frame | frame-data test |
| Heavy attack startup | ≤ 10 frames (current) | frame-data test |
| Hit feedback delay | sparks, number and sound on the same frame as damage | event-order test |
| Hit-stop | ≤ 0.07 s, never stacks | `hitstop_check` |
| Dodge | usable from recovery; i-frames 0.18 s | `input_check` |
| Enemy telegraph | ≥ 0.4 s for regular enemies, ≥ 0.6 s for the boss | frame-data test |
| Frame spikes during a heavy fight | no frame over 40 ms in a quiet-machine run | `tests/stutter_bench.gd` |
| Human rating | "responsive" from at least 4 of 5 testers | playtest form |

## 4. Manual checklist per release candidate (human, 45 minutes)
1. New game, skip and not skip the intro.
2. Play the whole mission on keyboard and mouse; note time per act.
3. Die once in each area; check respawn and state.
4. Save at a checkpoint, quit, continue; compare position, equipment, objective, puzzle state.
5. Fight the Warden three times: one win without medkits, one with, one death.
6. Open every screen (menu, settings, inventory, journal, results) with keyboard, gamepad and touch.
7. Run the five-wave arena (regression).
8. Record FPS (F3) at: beach, courtyard fight, research wing, boss.
9. Repeat 1–4 on Android and web.

## 5. Regression rule for the five-wave arena
Every Milestone 004 change must keep `run_tests`, `boss_check` and the courtyard parts of `world_check` green. The arena must still be reachable (through the courtyard) and complete. A separate "Arena Mode" menu entry was planned in Milestone 003 but is **not implemented** (`[PLANNED]`, decision for Milestone 004: add it to the main menu or drop it).

## 6. Known limitations to carry into the release notes
- Placeholder or greybox art on the branches that are not merged; the stylized characters exist only on `milestone-002`.
- Patrols use simple steering, one squad exists.
- Android and web are untested for Milestones 002 and 003.
- The Android build is debug-signed.
- Gamepad bindings are incomplete.
- Audio is procedural and unjudged in a real mix.
- No automated test proves that the game is fun; human playtests are required.

## 7. Reporting rules
Record each run as: date, commit, platform, test id, result (pass/fail/blocked), evidence (log line or screenshot), and the tester. A failed test blocks release until fixed or explicitly accepted by the owner with the limitation written into the release notes.
