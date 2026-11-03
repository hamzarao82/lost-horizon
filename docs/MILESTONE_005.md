# Milestone 005: The First Signal (audit and acceptance status)

Status date: 2026-11-03. Written after inspecting the repository, not from the brief. Legend: **V** = verified by an automated test or a screenshot that was actually run; **H** = needs a human or a device and has NOT been done; **P** = partly; **N** = not implemented.

## 1. Audit result
Most of the milestone's content already exists from Milestones 1–4 and is merged on `master` (live on GitHub Pages). This milestone therefore did not rebuild systems. It audited them against the acceptance list, measured performance, captured real screenshots, and recorded the gaps.

Implemented (see the milestone documents for detail): third-person combat with dodge/lock-on/combos, five-wave arena, health + armor + medkits, weapon and armor loot, teleport charges, stylized skinned characters (Blender-scripted), Outpost 17 with areas A–D, 15-objective quest `first_signal`, access card, three-switch power puzzle (order B, A, C), patrols with detection, Warden with two phases (40%), results screen, main menu, death screen, equipment screen, versioned save v2 with checkpoints, procedural audio (combat, UI, footsteps, ambience, radio, boss, mission complete), gamepad bindings, web/Windows/Android exports.

## 2. Acceptance checklist

| Criterion | Status | Evidence |
|---|---|---|
| Game launches | V | boot_check, web boot probe (about 29 s to reveal) |
| Main menu / entry point | V | screens_check; screenshot of the live web menu |
| Mission can be started | V | screens_check (New Game), playthrough_bot |
| Player explores the level | P | world_check; not walked by a human |
| Controls and camera | P | input_check, lockon_check, gamepad_check; feel not judged by a human |
| Combat works | V (logic) / H (feel) | run_tests, input_check, hitstop_check |
| Enemies detect and attack | V | patrol_check, run_tests |
| Enemy death and loot | V | run_tests, dressing_check |
| Access card collected | V | quest_chain_check, playthrough_bot |
| Locked access opens | V | door_check, world_check |
| Three-switch puzzle | V | puzzle_check, playthrough_bot |
| Research facility accessible | V | world_check, playthrough_bot |
| Warden encounter starts | V | boss_intro_check |
| Warden two phases | V | warden_design_check, boss_check |
| Boss can be defeated | V | playthrough_bot (kills Warden via receive_hit) |
| Mission completion | V | mission_check, playthrough_bot (completes exactly once) |
| Rewards exactly once | V | mission_check, quest_check |
| Save and reload | V | save_check, save_v2_check, screens_check (real Continue) |
| Checkpoint recovery | V | save_v2_check (real death then reload) |
| UI updates correctly | P | ui_layout_check (rect checks), some screenshots; touch layouts untested on a phone |
| No critical debugger errors | P | all suites show zero SCRIPT ERROR lines headless; windowed and web consoles not exhaustively reviewed |
| No major progression blockers | P | bot completes all six acts; a human has not |
| Whole mission completed start to finish by a human | **H, not done** | |
| Android 30 FPS on a device | **H, not done** | never run on a device |
| Windows 60 FPS | P | benchmark avg 86–97 FPS on integrated graphics, but frame spikes up to 124 ms in the first heavy fight (budget 40 ms) |
| Web 30 FPS | P | loads in about 29 s in desktop Chromium; frame rate on phones unmeasured |

## 3. Not implemented or partial against the brief
- Required objective for reading a military record (an optional document exists); radio objective not moved earlier; per-act banners; quest journal.
- Art quality is stylized low-poly, not comparable to a commercial reference title. Terrain, foliage density and lighting are improved but not hand-sculpted.
- Dedicated underground research interior: the research area is an above-ground compound plus command building (Area C/D), not an underground level.
- No licensed audio; all sounds are procedural and have not been judged by a listener.
- Android: debug-signed APK only, never run on a device.

## 4. Process notes
Screenshots of the running game and the performance work are recorded in `PERFORMANCE_BUDGET.md` and below once the agents report. A milestone is only called complete when every **H** row is verified by a person.

## 5. Verdict
Not complete by the brief's own rule: the whole-mission human run, Android device run and frame-spike budget remain unverified or missed. Everything else on the list is covered by tests that were run.

## 6. Screenshots of the running game (8 captured, 2026-11-03)
Captured windowed at 1280x720 by a script that teleported the player; therefore the quest tracker still shows the first objective and no results screen was reached. Files are kept outside the repository (scratchpad `m5shots`). Two were reviewed by the lead as well as the agent: interior and compound shots match the findings below.

| Shot | What is actually visible |
|---|---|
| Arrival / beach | readable, HUD fits; flat orange ground, sparse vegetation, one oversized foreground palm |
| Outer checkpoint | gate and name banner; no patrol in view |
| Compound | courtyard empty (no enemies in view) despite the wave counter: not a combat image |
| Power switches | three switch boxes in a bare grey room (greybox look) |
| Research terminal | bare room; "Terminal offline: restore power" text; no research dressing |
| Warden intro / phase 2 | best images: detailed Warden, boss bar, captions, embers; arena plain; a damage number overlaps a caption |
| Results | not reached by the script, so NOT verified visually |

**Visual defects, most noticeable first:** interiors and Areas C/D are bare grey boxes; ground is flat orange with sparse vegetation; the interiors look unfinished next to the Warden; a text overlap on the boss caption; a dark blob at the top edge of one frame (cause unknown). The brief's visual target is therefore **not met** for the interiors.
