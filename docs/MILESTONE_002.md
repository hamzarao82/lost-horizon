# Milestone 002 report: stylized visual upgrade

Status date: retrospective (written 2026-11-13; the work predates this document — see branch `milestone-002`, worktree `lost-horizon-m2`/`m8`/`m9` in various sessions, and `docs/milestone-002/` in the planning-docs repository for the original inspection report and plan). Legend: **Implemented**, **Verified** (a test was actually run), **Not tested**.

## What this milestone was
Replaced Milestone 001's box-placeholder characters and the flat arena look with Blender-scripted stylized low-poly GLB models (skeleton + clips), a small reusable environment kit, weapon and armor models, and the visual/animation plumbing (`SkinnedVisual`, `AnimationDriver`) needed to drive them from the existing combat system without changing combat logic.

## What was built
| Area | Built | Evidence |
|---|---|---|
| Characters | Player, soldier, heavy, elite and Warden GLBs (skeleton + clips: idle, walk, run, sprint, jump, fall, land, guard, light 1-3, heavy, sprint/air/spin attack, dodge, hit, death, and the Warden's slam/flurry/shockwave/roar), authored by `tools/blender/anim_clips.py` and the character-design scripts | `anim_sync_check` (122): clip mapping, strike-frame alignment, fallbacks, missing/broken-model safety |
| Visual adapter | `SkinnedVisual` + `AnimationDriver`: attack clips are scrubbed to the combat system's frame counter rather than played freely, so damage timing is unchanged from Milestone 001 | `anim_sync_check`, `docs/ANIMATION.md` |
| Weapons | Several weapon GLBs with distinct stats (improvised blade through the claymore; see `docs/WEAPON_ART.md`) | `verify_weapons` (106) |
| Environment kit | A reusable low-poly prop kit (containers, barrels, fences, barricades, a watchtower, palms, rocks — see `assets/environments/kit/` and `docs/ENVIRONMENT_KIT.md`), merged into a handful of draw calls per arena build | `env_kit_check` (42) |
| Model validation | A general GLB import checker (scale, origin, skeleton, materials) | `verify_glb` |
| Effects | Visual polish pass on hit sparks, dust and boss telegraphs alongside the new character silhouettes | `fx_check` (28, shared with Milestone 001) |

## Acceptance
All rows above are **Implemented and Verified** by the suites listed, which still exist and still pass today. Combat numbers (frame data, damage, timing) were explicitly preserved — `run_tests`, `input_check`, `hitstop_check`, `boss_check` from Milestone 001 were re-run on this branch and passed unchanged, confirming the visual swap did not alter gameplay.

## Performance (Intel UHD 620 laptop, `tests/benchmark.gd`, skinned characters + kit environment)
Avg FPS 91, 1% low 39 to 40, peak draw calls 111 (down from Milestone 001's 177 to 181 box characters, because the kit's decor merges into a handful of draws). Decor draw calls were merged into 4 draws per kit build via static mesh merging.

## Known limits at the time
- Stylized low-poly, not high-detail or hand-sculpted; the project's standing visual target (something closer to the owner's reference images) was never reached at any point in the project — this remains an open gap through every later milestone and is explicitly deferred to Milestone 013 (the graphics overhaul).
- No world content yet (Outpost 17's explorable areas are Milestone 003); this milestone only re-skinned the existing arena and characters.
- Web and Android were not re-measured with the new art in this milestone specifically (the combined cost of `milestone-002` content was first measured only when it was later merged with other branches — see `PERFORMANCE_BUDGET.md`, "Unverified").
- As with Milestone 001, this document is written after the fact from the surviving test suites and docs (`ANIMATION.md`, `CHARACTER_ART.md`, `ENVIRONMENT_KIT.md`, `WEAPON_ART.md`), not from a contemporaneous log.
