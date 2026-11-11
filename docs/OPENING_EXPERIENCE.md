# The Opening Experience (plan, audit and status)

Status date: 2026-11-11. This document is written **before** implementation, as the brief required. Legend: **Implemented**, **Partial**, **Planned**, **Verified** (a test or screenshot was run), **Not tested**. At the time of writing nothing in section 6 is implemented.

## 1. Scope
Only the opening story and the first survival minutes: a cinematic main menu background, a speedboat-and-storm cinematic, the shipwreck and treasure event, and a short playable injured recovery. Outpost 17 is not redesigned, is not shown, and the island's mystery, the organization, the Director and Project Black Site are not mentioned. The protagonist wants his payment back and wants to leave the island.

## 2. Story canon for the opening
The protagonist is a professional thief. He has just completed a heist for an extremely wealthy organization and is paid in a bag of gold and diamonds. He flees by speedboat. A hurricane throws him into the sea; he washes up on an island he has never heard of (an accident, not a destination). On the beach he sees his bag caught in a tree, and a guard with two enslaved workers take it away. He sees this only briefly, injured. The player must not learn where the bag goes.

### Conflicts with existing lore and code (to resolve, not to ignore)
| Where | Existing | Conflict | Plan |
|---|---|---|---|
| `scripts/story/intro.gd` captions | "A storm hit the transport... the ship broke apart" | the protagonist was on a transport, with no memory | replaced by the new cinematic; the old intro is kept only as a fallback for headless runs |
| `docs/NARRATIVE_BIBLE.md` and the ending (`scripts/story/campaign_ending.gd`) | the protagonist as a witness aboard a transport (a proposal needing approval) | contradicts "thief by speedboat" | the new canon resolves the "why is the protagonist here" gap; the ending's closing captions must be rewritten later (listed, not part of this milestone) |
| first-mission radio lines (`world_flow.gd`, R1 to R3) | start playing at game start | they introduce the island's mystery | delayed until the opening quest is finished |
| start equipment | `Inventory.STARTING_WEAPON = improvised_blade` | the brief wants the stick to be found | see section 5 |
| `docs/STORY_AND_MISSION_FLOW.md` Act I | the first mission begins with the player already armed on the beach | the new opening comes before it | the opening quest runs first; `first_signal` is untouched |

## 3. Audit: what the project already has
| Need | Existing system (verified in the repository) | Reuse or new |
|---|---|---|
| Startup flow | `scenes/boot/Boot.tscn`, `scripts/core/boot.gd`: loads and warms the world behind an early `MainMenu` (`scripts/ui/main_menu.gd`, 275 lines); New Game or Continue then starts Main | reuse |
| Menu look | a dark `ColorRect` plus `MenuEmbers` (`scripts/ui/menu_embers.gd`) | replaced by a new background node; the buttons stay |
| Intro | `StoryIntro` (`scripts/story/intro.gd`, 209 lines): CanvasLayer at layer 150, pauses the tree, skip by key, click, tap or button, 0.4 s skip grace; started by `QuestManager._run_intro()`; `intro_done` is saved, set synchronously, and never replays on Continue; `QuestManager.should_play_intro()` is a tested static rule | reuse the hook, the flag, the pause and skip pattern; replace the content |
| Player visual | `SkinnedVisual` plus `AnimationDriver` over `assets/characters/player.glb`; clips: idle, walk, run, sprint, jump_start, fall, land, guard, light_1 to 3, heavy, sprint_attack, air_attack, spin, dodge, hit, death (authored in `tools/blender/anim_clips.py`) | reuse |
| Missing clips | lying injured, wake up, sit up, hold side, stand slowly, limp, search wreckage, pick up, equip clothing, steer a boat, fall into the sea | see section 4 |
| Camera | `scripts/camera/camera_controller.gd` (109 lines, third-person follow, collision); the intro already uses a separate `Camera3D` | a separate cinematic `Camera3D` per scene |
| Items | `Inventory`, `ItemData` with slots (primary weapon, body, helmet, gloves, legs, accessory) and categories; `Pickup` scene; item icons from `tools/gen_icons.gd`; `improvised_blade`, `bandage`, `health_potion` (Medkit), `light_tactical_armor`, `armor_patch` exist | new items: `wooden_stick`, `salvaged_jacket`, `medical_supplies` |
| Gear visuals | `scripts/visual/gear_visuals.gd` table for helmet, gloves and boots | extend with the jacket (body tint) |
| Beach and props | the beach terrain, `boat_wreck.glb`, palms, rocks, crates, barrels, bushes in `assets/environments/kit/` and `ArenaDecor` | reuse; no new outpost view |
| Ocean | a water plane with a shore foam strip exists in Dead Coast's builder (`scripts/regions/dead_coast/`) | reuse the idea for a wave shader |
| Quests and saves | `QuestManager` (event-driven quests, a pinned tracker quest), `SaveManager` v4 sections; WorldState flags `[a-z0-9_]` up to 48 characters | new quest `opening_survival`; new flags `opening_*` |
| Audio | procedural sounds from `tools/gen_sfx.gd` (ambience loops coast, jungle, facility; thunder-like `hit_heavy` is borrowed by the old intro) | add ocean, storm, thunder, wave crash, rain, wind sounds |
| Tests | 94 headless suites incl. `quest_check`, `boot_check`, `menu_check`, `screens_check` | add opening suites; run all |

## 4. Animations: what is missing and the cheapest honest fix
No new bone clips exist and none are authored by this milestone unless Blender work is approved. The least expensive way that still looks acceptable:
| Needed | Fix | Quality |
|---|---|---|
| Lying injured | the `death` clip held on its last frame, body slightly rotated | good |
| Regaining consciousness, sitting up, standing | the `death` clip **played in reverse** (a natural rise), eased, then `idle` | good |
| Holding the injured side | the `hit` clip held at its reaction pose, plus a slow breathing sway on the visual root | acceptable |
| Limping | `walk` at 55% speed with a periodic root dip and lean, a short stride | acceptable |
| Searching wreckage, picking up, equipping | a crouch using the `land` clip held plus a root lowering; a short "lift" tween; a clothing change is a tint swap | acceptable |
| Opening eyes, blurred vision | a screen effect: gaussian blur and vignette that clear over seconds, eyelid black bars | good |
| Steering the boat | `idle` posed at the wheel with hand sway on the root | acceptable |
| Thrown into the sea | a tumbling tween on the visual root plus splash particles, cut to black | acceptable |
Recommendation for Milestone 13: author real clips (lie, wake, sit, stand, limp, pickup, steer, fall) in `tools/blender/anim_clips.py` and swap them in through the same `CLIP_SPECS` table. Report missing clips in the final report.

## 5. Design decisions
1. **Cinematic**: a real-time 3D scene (`OpeningCinematic`) built from procedural low-poly meshes (speedboat, treasure bag with gold and diamonds, ocean plane with a wave shader, cloud layers, rain particles, lightning light flashes) and the existing player model. Twelve scenes with several camera angles and smooth transitions, one scripted timeline, about 50 to 60 seconds. On web the same scene runs with fewer particles and vertex-only materials. Skippable at any time with any key, click, tap or a Skip button; skipping never softlocks.
2. **Main menu**: a 2D layered background (cheap): dark sky, wave bands drawn by a canvas shader, a distant island silhouette, lightning flashes and bolts, thunder, and a baked side-profile of the protagonist (the player model rendered once into a texture) with a few very brief combat-pose flashes. No live 3D in the menu, so loading behind the menu is not slowed; the existing embers stay as a fallback.
3. **Beach sequence** (scripted, then playable): blurred wake with the guard and two workers taking the bag (shown from the player's point of view while injured, from a distance, no destination shown); then the recovery animation sequence; then control returns in an injured state (health about 35%, limp speed, attacks locked).
4. **Survival tasks** as a new quest `opening_survival` (pinned, region Outpost 17, does not block `first_signal`): (a) find medical supplies in the wreckage, (b) treat your wounds (use a medkit), (c) find clothes, (d) find something to defend yourself (the wooden stick), then the injury restrictions lift and the normal first mission tracker returns. The arrow leads to each item. Failsafe: if the player has not taken an item within 60 seconds of control, a caption points to it; if the stick is still missing after 120 seconds it is placed in the bag so nobody can be stuck unarmed.
5. **Start equipment**: in a real New Game the player starts with no weapon; `wooden_stick` (damage multiplier 1.0, the same as the improvised blade, so nothing is weakened) is equipped on pickup and is the starting weapon afterwards. Headless runs and all existing tests keep the improvised blade, so no existing suite changes.
6. **Persistence**: `intro_done` already covers the cinematic and the wake sequence; new flags `opening_done` and `opening_<step>` persist quest steps; Continue never replays; a reload in the middle of the survival tasks resumes at the right step; NPCs never spawn twice.
7. **Performance**: the menu uses a low-resolution canvas shader; the cinematic only builds when New Game is chosen; particle counts scale with the quality preset; nothing runs while the menu is idle beyond a timer-driven lightning flash.
8. **No outpost**: the wake camera and the playable beach area are framed so no outpost building, wall or sign is visible; the first mission's "Outpost 17" banner appears later.

## 6. Work plan
| # | Piece | Files (planned) | Status |
|---|---|---|---|
| 1 | Cinematic main menu background | `scripts/ui/menu_background.gd`, `main_menu.gd` hook, sounds | Planned |
| 2 | Speedboat and storm cinematic | `scripts/story/opening_cinematic.gd`, `scenes/story/OpeningCinematic.tscn`, `scripts/story/opening_assets.gd` (procedural meshes), storm sounds | Planned |
| 3 | Shipwreck, treasure event, recovery, survival gameplay | `scripts/story/opening_beach.gd`, new items, `opening_survival` quest, player injury hooks, `QuestManager._run_intro` chain | Planned |
| 4 | Tests and docs | `tests/opening_*_check.gd` | Planned |
| 5 | Re-balance of first-mission radio timing; ending captions consistent with the thief canon | `world_flow.gd`, `campaign_ending.gd` | Planned (separate) |

## 7. Acceptance criteria and status
| # | Criterion | Status |
|---|---|---|
| 1 | Main menu presentation works | Planned |
| 2 | New Game starts the new opening | Planned |
| 3 | The speedboat cinematic plays | Planned |
| 4 | Storm and shipwreck sequences work | Planned |
| 5 | The protagonist wakes on the beach | Planned |
| 6 | The treasure retrieval event plays | Planned |
| 7 | The injured recovery sequence plays | Planned |
| 8 | Medical supplies can be collected | Planned |
| 9 | Clothing can be collected and equipped | Planned |
| 10 | A wooden stick can be collected and used | Planned |
| 11 | Control transitions correctly into gameplay | Planned |
| 12 | Continue does not replay the opening | Planned |
| 13 | Skipping works | Planned |
| 14 | Existing combat, inventory and save systems remain functional | Planned (existing suites) |
| 15 | Existing automated tests continue to pass | Planned |

## 8. Risks
- The cinematic is procedural and low-poly: it will look stylized, not like a film. Camera work and effects carry it.
- Reverse-played death and held poses are a stand-in for real animations (section 4).
- A 3D cinematic on web adds load and memory; it is built only on New Game and freed afterwards; the web load budget is already over (about 32 to 42 s).
- Starting unarmed changes the first minutes for every New Game: attacks are locked until the stick is taken, with a failsafe.
- Nobody has played it; pacing and length are unjudged. Target: about 60 s cinematic, 90 s beach recovery.
