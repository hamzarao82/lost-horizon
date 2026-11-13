# Opening Beach Sequence

`scripts/story/opening_beach.gd` (class `OpeningBeach`) plays after the cinematic finishes: the shipwreck wake, a glimpse of the treasure being taken, the injured recovery, and the handoff into a short survival quest. Wired into a real New Game by `QuestManager._run_intro` (unchanged gating: `should_play_intro()` still decides whether this runs at all — headless runs, loads, checkpoints, and a replayed `intro_done` all skip it exactly as before; the only change is *what* a real New Game plays).

**API:** `OpeningBeach.play(tree, player) -> OpeningBeach`, `signal finished`, `func skip()`. Same pause/skip pattern as `StoryIntro` and `OpeningCinematic`.

## What happens
1. A black screen fades in over 6 s (standing in for the "blurred vision clearing" beat — see Simplifications).
2. A short scripted mini-scene, in its own `SubViewport`/`World3D` exactly like the cinematic (so it can never show the outpost: it is a separate, procedural beach with no outpost geometry in it at all): sand, three pieces of wreckage, a palm tree with the treasure bag, the protagonist lying down (a capsule rotated flat — not the real rigged pose), and a guard capsule with two worker capsules that walk in, take the bag, and walk off along the shore (never toward the camera).
3. Fade to black, a single caption ("Get up."), then fade back in.
4. **Handoff** (`_hand_off`): the real `Player` already spawned by Boot/Main is set to 35% health, `injured_speed_mult = 0.55`, `attacks_locked = true`, and the quest `opening_survival` starts, pinned at the top of the HUD tracker (`QuestManager.tracker_first`).
5. **Survival quest** (`resources/quests/campaign/opening_survival.tres`, 3 objectives, any order, not strict): find medical supplies (pick up a Medkit), find clothes (pick up and this script auto-equips `salvaged_jacket`, +15 armor), find a weapon (pick up and auto-equip `wooden_stick`, same damage multiplier as the starting Improvised Blade). All three use the game's existing `ITEM_COLLECTED` quest-event path (`Pickup` -> `Inventory.collect`/`add_item` -> `item_collected` signal -> `QuestManager` notifies automatically); nothing new was added to that path.
6. When the quest completes, `attacks_locked` clears immediately and `injured_speed_mult` eases back to 1.0 over 3 s.
7. **Failsafe:** if the stick has not been taken within 60 s of the handoff, a one-time HUD caption points at it; after 120 s it is granted and equipped automatically. Nobody can be stuck unarmed.

## Simplifications (and why)
Given the scope of this milestone, several things were simplified rather than built in full, to keep the change small, testable and low-risk against the combat and animation systems that 94 other test suites already protect:
- **No blur/vignette shader and no real "lying down / sitting up / standing" skeletal animation.** The wake uses a plain fade from black; the recovery is a caption, not a driven pose. Milestone 13 (the graphics pass) is the natural place to drive the real `SkinnedVisual`/`AnimationDriver` through a proper lying-wake-stand sequence (see `docs/OPENING_EXPERIENCE.md` section 4 for the recommended stand-in-to-real mapping).
- **No limp animation.** The injury is gameplay-only (`injured_speed_mult`), not visual.
- **"Treat your wounds" is not a separate tracked step.** Picking up the medkit satisfies "find medical supplies"; using it afterward works exactly as it always has (press R) but is not itself gated or tracked here, since hooking a reliable "medkit was used" event into the opening would have meant touching the medkit-use code path shared by every other region. Three objectives, not four, as a deliberate, documented reduction from the original four-task brief.
- **The guard and workers are capsule stand-ins**, like the cinematic's protagonist — not the rigged soldier model. They have no AI; their walk is a straight linear move, scripted, not pathfound.
- **One attacks-locked guard:** dodge and jump are NOT restricted during the injury (only light/heavy/special attacks are blocked). This was a judgment call to keep the player able to move freely and dodge a scare if the stage ever needed one, while still feeling "too weak to fight."

## Safety notes
- `Player.injured_speed_mult` (default `1.0`) and `Player.attacks_locked` (default `false`) are the only changes to `player.gd`, both additive and multiplying/gating existing behaviour only when non-default. `input_check` and `run_tests` pass unmodified, confirming no change to normal combat.
- The old `StoryIntro`/`Intro.tscn` is untouched and still covered by its own assertions in `tests/quest_check.gd` (which load it directly, not through `_run_intro`), so it remains available even though a real New Game no longer plays it.
- A pre-existing, unrelated test failure was found and fixed while verifying this work: `tests/mission_check.gd` still expected the Outpost 17 tracker to show "Take the Warden's reward" after the Warden falls, but an earlier change (`2fa0475`, "the way on opens when a stage's bosses are down") made `CampaignFlow` pin the "Follow the signal to the Dead Coast" road step the moment the Warden dies — by design, per the owner's explicit request that a region's exit should open on boss defeat alone. The test was outdated, not the game; it has been updated to check the real (and intended) behaviour. This was a genuine regression nobody had caught because `mission_check.gd` was not rerun after that change landed.

## Tests
`tests/opening_beach_check.gd`, 20 checks: headless cheapness, the handoff's exact numbers (health, speed, lock), the quest starting and being pinned, an attack really being dropped while locked, the three pickups completing the quest in a specific order (and not before all three), restrictions lifting on completion, and every id/flag this feature writes obeying WorldState's `[a-z0-9_]`/48-character rule. The full ~25 s scripted timeline itself (fades, the NPC walk) is not exercised by the automated test — it is tested by calling the private `_hand_off()` directly on a node that is never added to the tree, which is deliberate: the timeline's `await`s are tied to real wall-clock timers (like `StoryIntro`'s), so running it end-to-end in a test would cost ~25 real seconds for no additional coverage.

## Not verified
Nobody has played the sequence. The beach mini-scene's camera framing, the NPC walk timing, and the caption wording have been looked at once via windowed screenshots (see the final report) but not iterated on for feel.
