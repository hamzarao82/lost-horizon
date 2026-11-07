# Campaign ending

Status date: 2026-11-07. Code: `scripts/story/campaign_ending.gd`. Test: `tests/campaign_ending_check.gd` (53 checks).

## What it does
When the world flag `campaign_complete` turns on (the Iron Fortress sets it after the Director falls and the final transmission is sent), `CampaignEnding` starts once:
1. fade to black (about 1.2 s), the game is paused, the HUD is hidden, ambience and music are ducked to silence, the `mission_complete` sound plays;
2. seven closing captions (original text, in `CampaignEnding.BEATS`), each 4.5 to 6 s, skippable one at a time with Space, Enter or Esc;
3. a statistics screen: **campaign** (regions completed x / 5, missions completed, time played, enemies defeated) and, separately, **optional discoveries** (secrets found x / y, documents read);
4. the credits (the existing `StoryEnding.CREDITS` lines);
5. a choice: **Continue Exploring** (unpauses, restores the HUD and sound, every region stays open) or **Main Menu** (autosaves, resets the run state, loads the menu scene so Continue loads the file just written).

`ending_seen` is set when it starts, so it plays automatically once. Both flags are saved (underscore ids, 14 and 11 characters).

## Rules that are tested
- It starts only when `campaign_complete` turns on, never for another flag, never for the `*` wildcard a loaded save emits, never when `ending_seen` is already set.
- Loading a save that has `campaign_complete` does not replay it.
- Finishing the optional arena chain (`final_transmission`) no longer opens the old "Thanks for playing" screen. The legacy `ending_started` signal still fires so existing listeners keep working. In headless runs the old code returned before showing the scene anyway, so this is proved by a source check that `load(ENDING_SCENE)` is gone, not by a behaviour difference. This fixes contradiction 1 in `CAMPAIGN_AUDIT.md`.
- After Continue Exploring the tracker shows "After the signal / Explore freely: every region is open" when no quest is active; the player is alive and processing; all regions stay unlocked.
- Flags survive a WorldState round trip and a real `SaveManager` save and load; a new game after the menu choice starts without them.

## The story beats
They follow the proposal in `NARRATIVE_BIBLE.md` section 12: the transmission reaches the outside, the island's command is exposed but not destroyed, the lost transport's manifest names a witness the organization tried to bury (this is the bible's *proposed* reason for the protagonist being on the transport and needs the owner's approval), and one thread stays open (the counter below Sublevel 1 and the voice in the Blackwood). No new antagonist and no cliffhanger.

## Status
| Item | State |
|---|---|
| Trigger once, not on load, not from the arena chain | implemented, verified by tests |
| Beats, stats screen, credits, choice | implemented, verified by tests; looked at screenshots at 1280x720 and 800x360 |
| Continue Exploring and post-campaign tracker line | implemented, verified by tests |
| Main Menu choice | implemented; the test checks the choice, the flag reset and the unpause with the scene change switched off; the real scene change to `Boot.tscn` was not run |
| Ambience and music duck | implemented behind guarded calls (`AudioManager.set_ambience_duck`); nobody has listened |
| Replay from the main menu | **not wired**: `CampaignEnding.start(tree, true)` exists and is tested (it touches no flags), but no menu entry calls it, because the menu cannot read the saved flags before a save is loaded |
| 1600x720 layout | not captured; the interface scales with the window |
| "Missions completed" | counts the quest manager's completed list, which includes the optional arena chain and the bridge quests |
| Human playthrough of the ending | **not done** |
