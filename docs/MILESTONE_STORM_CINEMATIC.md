# Milestone 1 (Opening series): The Storm. Cinematic opening, the speedboat journey

Status date: 2026-11-14. This is the brief, an audit of the shipped cinematic against every beat and acceptance criterion, and the list of gaps. The brief is named "Milestone 1" in the owner's opening series; it is **not** the same as `MILESTONE_001.md` (the first combat prototype). The implementation already exists (`OPENING_CINEMATIC.md` describes its API and tests); this document records how far it meets the brief, honestly. Legend: **Implemented**, **Partial**, **Not built**, **Verified** (a test or a real screenshot), **Not tested**.

## 1. Scope
Only the speedboat sequence and its transition to black. The beach, the guard and workers, Outpost 17 and the survival section belong to later pieces (`OPENING_BEACH.md` covers what was built for those). Story canon: a professional thief, paid in a bag of gold and diamonds, flees by speedboat, is caught by a hurricane; the island is an accident. The cinematic must not mention a mission, an organization, a signal, Outpost 17 or any island history.

## 2. Where it lives
| Part | Path |
|---|---|
| Timeline data (12 scenes, camera, storm level) | `scripts/story/opening_timeline.gd` |
| Cinematic scene and playback | `scripts/story/opening_cinematic.gd` (own `SubViewport` and `World3D`) |
| New Game hook | `QuestManager._run_intro()` creates it, then chains to the beach on `finished` |
| Tests | `tests/opening_cinematic_check.gd` (15 checks) |
| Sounds used | `menu_wind.wav` (looping bed), `menu_thunder.wav` (strikes), `AudioManager.set_region_ambience(&"outpost", 3.0)` for the final crossfade |

## 3. Beats against the brief
| Beat of the brief | Shipped scenes (duration) | Status |
|---|---|---|
| A. A successful job: protagonist on a speedboat, relaxed, bag visible | `aerial` (5 s), `tracking` (5 s), `bag_closeup` (4 s), `face_closeup` (4 s); storm level 0 | **Implemented.** The protagonist is a capsule stand-in, not the real model; "relaxed and confident" is carried only by camera and calm weather, there is no pose or animation |
| B. Open water: wide shot, side tracking, close-ups of protagonist and bag, optional horizon look | the same four scenes | **Implemented** except the optional horizon look |
| C. The weather changes: darkening clouds, wind, rain, thunder, distant lightning, built gradually | `clouds_appear` (storm 0.15), `storm_builds` (0.4) | **Implemented.** Rain particles switch on above storm 0.3; lightning frequency rises with the storm; wind bed is constant, not rising |
| D. The hurricane: boat struggles, protagonist loses control, bag displaced if feasible, careful shake | `struggle_wheel` (0.55), `waves_hit` (0.7), `overwhelmed` (0.9) | **Partial.** Escalating storm and wave framing exist; **no camera shake was found in the code, and the bag is parented to the boat and is not shown sliding or falling**, so "bag displaced" and "loses control" are implied by framing only |
| E. Blackout: violent wave, camera submerged or thrown, sound muffled, fade to black | `thrown_overboard` (1.0), `to_black` (1.5 s), `ambience_crossfade` (3 s) | **Partial.** The fade to black and the ambience crossfade work. **There is no muffled or underwater sound filter, and no splash or submersion effect** |

Total length 50.5 s (target in the brief: not specified; `OPENING_EXPERIENCE.md` targeted about 60 s).

## 4. Audio against the brief
| Wanted | State |
|---|---|
| Ocean ambience | **Partial**: the shared menu wind bed and the beach ambience crossfade; no dedicated open-sea loop for the boat scenes (a waves loop, `menu_waves.wav`, exists for the menu but is not used here) |
| Boat engine | **Not built.** No engine sound exists in `assets/audio` |
| Wind rising | **Partial**: a constant bed, not a rise |
| Rain | **Not built as sound**; rain is only visual particles |
| Thunder | **Implemented**: `menu_thunder`, played with each lightning flash |
| Storm impact | **Not built** |
| Muffled sound at blackout | **Not built** |
| Quality of generated audio | **Not judged.** Nobody has listened to any of it, and the brief asks that generated audio be checked for quality before use |

## 5. Technical requirements
| Requirement | Status |
|---|---|
| Existing architecture preserved | **Met.** No scene or system replaced; the old `Intro.tscn` and `StoryIntro` remain and are still tested |
| Uses existing character and animation resources | **Not met.** The protagonist and boat are procedural capsule and box shapes. The rigged player model and its clips are not used; no speedboat asset exists in the project, and none was created beyond the procedural hull. This was reported, not hidden, in `OPENING_CINEMATIC.md` |
| Performant under GL Compatibility | **Plausible, not measured.** 160 CPU particles for rain, simple meshes, flat-coloured ocean plane (no wave shader). No frame-rate or draw-call figure was taken for the cinematic |
| Windows and browser compatibility | **Windows:** the headless export smoke test passes; the cinematic itself was seen in real-renderer screenshots on desktop. **Browser:** **not tested**; the cinematic has not been run in a web build |
| Goes through the New Game flow | **Implemented, test-covered** at the code level (`QuestManager._run_intro`); never run end to end by a person |
| Player input cannot interfere | **Implemented**: layer 150, pauses the tree, restores pause state on finish |
| Skip, without leaving audio or camera state behind | **Implemented, verified**: `finished` fires exactly once on full play, skip, double skip, and early free; pause state restored. Audio-player cleanup after a skip is covered only indirectly |
| Gaps reported rather than silently substituted | **Done** in `OPENING_CINEMATIC.md` section "Visual honesty" |

## 6. Acceptance criteria
| # | Criterion | Status |
|---|---|---|
| 1 | New Game starts the cinematic | **Implemented**; code path tested, no human run |
| 2 | Protagonist visibly travelling on a speedboat | **Partial**: a capsule on a procedural boat; recognisable as a figure on a boat, not as the game's character |
| 3 | Payment bag clearly established | **Implemented** (`bag_closeup`, `TreasureBag` with coin discs); judged by screenshot only |
| 4 | Storm builds progressively | **Implemented, verified** (storm level monotone from scene 5 to 10, asserted in the test; seen in screenshots) |
| 5 | Boat overwhelmed by the hurricane | **Partial**: framing and escalation; no physical capsize or bag displacement |
| 6 | Clean transition to black | **Implemented** (`to_black` then `ambience_crossfade`) |
| 7 | Next milestone can begin from the transition | **Implemented**: the beach sequence starts on `finished` |
| 8 | Works on Windows and in the browser | **Windows partly; browser not tested** |
| 9 | No unrelated systems broken | **Verified**: the full regression (97 suites, zero failures) was run with the cinematic in place |

By the brief's own rule ("complete only when" all criteria hold), **this milestone is not complete**: criteria 2, 5 and 8 are partial or untested.

## 7. Known limitations
- Stand-in shapes for the protagonist and boat (Milestone 13 candidates, per the earlier docs).
- No camera shake, no bag motion, no capsize, no splash.
- Missing audio: engine, rain, storm impact, muffled underwater.
- Constant wind rather than a rise.
- Not run in a browser; no cinematic-specific performance numbers.
- Pacing and length unjudged by a person.

## 8. What would close the gaps
1. Add a short camera shake driven by storm level (cap the amplitude so the shots stay readable) and animate the bag sliding on `waves_hit` and leaving the boat on `thrown_overboard`.
2. Generate an engine loop, a rain loop and a heavy impact in `tools/gen_sfx.gd` (appended, old sounds byte-identical) and add a low-pass filter on the master bus during `thrown_overboard`, removed on finish and on skip. The audio budget is at 3 MB, so the new sounds must be short or shared (see `MILESTONE_012.md`).
3. Reuse `menu_waves.wav` as the open-sea bed and ramp the wind volume with storm level.
4. Replace the capsule with the real player model in a `SubViewport` (the same step that would put him in the main menu, see `MILESTONE_000_MAIN_MENU.md`), and use the idle clip.
5. Export the web build, run the cinematic in a browser, and record load time, frame rate and memory.
6. Measure the desktop frame time and draw calls of the cinematic and add them to `PERFORMANCE_BUDGET.md`.
7. Have a person watch it start to finish and judge pacing and clarity.

Steps 1 to 3 are small and testable by the existing timeline test style. Step 4 is the real work. Steps 5 to 7 need a browser or a person.
