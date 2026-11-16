# Story and quests

Resource-driven, event-driven quest layer plus an opening and an ending. Nothing in a scene hardcodes a quest: progress comes from gameplay events.

## The story

A professional thief takes a job from a wealthy organization. He breaks into the target site, completes the heist, and is paid a bag of gold and diamonds.

He flees by speedboat. A hurricane wrecks the boat on an unknown island, and he is left alone on the shore.

On the beach he finds the trail of the bag. A gate guard and two workers carried it off after the storm. He follows the trail inland and reaches a settlement. Only when he finds its sign does he learn it is called Outpost 17.

He searches the settlement for the bag. On the way he passes the research area and the command hall. He fights the Warden.

The bag is recovered from a sealed store in the command building. The store door opens only when the Warden is down.

As soon as he has the bag, an alarm starts a lockdown. Shutters close the north and south exits, and guards come for him. He has to find the breaker and throw it before he can leave.

When the breaker is thrown, the shutters lift and the opening ends. The regional campaign follows:

1. **Dead Coast**
2. **Blackwood**
3. **Research Complex**
4. **Iron Fortress**
5. **The Director**: the last fight of the campaign.

Each region has its own quest chain, and the next region opens when the previous one's exit flag is set.

## Files

| File | Role |
|---|---|
| `scripts/quests/objective_data.gd` | `ObjectiveData` resource: id, text, type (INTERACT, ENTER_AREA, KILL_COUNT, WAVE_CLEARED, ITEM_COLLECTED, FLAG, BOSS_DEFEATED, DISCOVER), targets, count, progress label |
| `scripts/quests/quest_data.gd` | `QuestData` resource: id, title, prerequisites, objectives, rewards (item ids), `next_quest`, start/complete captions, `validate()` |
| `scripts/quests/quest_manager.gd` | Autoload `QuestManager` (no `class_name`: it would clash with the autoload) |
| `scripts/quests/quest_state.gd` | `QuestState.sanitize()` for save data |
| `resources/quests/` | The quest resources, one folder per region |
| `scripts/story/intro.gd`, `scenes/story/Intro.tscn` | Opening |
| `scripts/story/ending.gd`, `scenes/story/Ending.tscn` | Ending and credits |
| `scripts/ui/hud.gd` | Quest tracker and subtitle queue (presentation only) |
| `tests/quest_check.gd` | Headless quest checks |

## Event contract

QuestManager listens, it never calls into gameplay (apart from handing out rewards through `Player.inventory.add_item`).

| Source | Signal / hook | Becomes |
|---|---|---|
| `WorldState` autoload | `interacted(id)` | INTERACT |
| | `area_entered(id)` | ENTER_AREA |
| | `flag_changed(id, true)` | FLAG |
| `WaveManager` (found via `node_added`) | `wave_cleared(index)` | WAVE_CLEARED, progress = highest cleared wave |
| | `all_cleared` | WAVE_CLEARED with the last wave number |
| `Enemy` (via `node_added`) | `defeated` | KILL_COUNT (display name, once per enemy instance); BOSS_DEFEATED for the group `boss` (`"The Warden"` becomes `warden`) |
| `Inventory` (via `node_added`) | `item_collected(item, kept)` | ITEM_COLLECTED when kept |

The world side emits the interaction and flag ids that the quest resources name. QuestManager itself sets `has_keycard` when the Warden is defeated (and also works without WorldState).

Rules:
- **Duplicate protection.** A set objective counts each distinct target once; a kill counts once per enemy instance; a quest completes and pays out exactly once (`completed` and `_rewarded`).
- **Order independent.** Events are remembered (`_history`), so an event that happened before its quest began still counts when that quest starts, and a flag that is already set counts at once.
- **Impossible steps after a load.** `reconcile_impossible()` credits a required step only when saved state proves it done: an item already recorded as collected, or a kill whose named targets are bosses the saved world marks defeated. Every other step is left alone.
- **Rewards** go through `Inventory.add_item` (weapons and armor only equip if better; medkits stack). If no player exists at that moment they stay queued, and are saved, until one does.
- **Captions.** `start_captions` / `complete_captions` are emitted on `caption_requested` and queued by the HUD. `QuestManager.say(text, seconds)` is available to anything else that wants a subtitle line.

## Tracker and subtitles

- Tall screens: tracker (title, objective with its progress count) in the left column at y=205, below the bars, the teleport label and the pause button.
- Short screens (fallback; with the project's `canvas_items` + `expand` stretch a window or phone is never shorter than 720 logical pixels, so an 800x360 window is really 1600x720): top centre at y=46, hidden while the boss bar is up.
- Subtitles: bottom centre, bottom edge 120 px above the screen edge (the toast sits at 110). Up to three lines; at most 8 lines queued.
- Both labels are capped (tracker objective two lines, subtitle three) so a long text can never grow over other widgets.

## Opening and ending

- **Opening** (about 22 s): captions on black, then a slow camera push toward the thief and the title card. Skip with any key, click, tap, gamepad button, or the Skip button (a 0.4 s grace period avoids accidental skips). The game is paused while it plays (the intro keeps running) and unpaused on exit.
- It plays only on a fresh game: not under the headless driver, not after loading a save, not after a death restart, not when quest progress exists, and only once per run (`intro_done`; a deliberate Restart or Play Again does not repeat it).
- **Ending:** when the final quest completes, the final captions play, then a screen "Thanks for playing" with credits, **Play Again** (clears run state through `SaveManager.reset_runtime_state()`, which also restarts the quests and the world flags, then reloads) and **Quit** (hidden on web and mobile).

## Saving

- The save gains an optional `quests` field (version stays 1): active quests with progress, completed ids, rewarded ids, pending rewards, event history, `intro_done`, and the `WorldState` flags. Saves from before the quest layer load fine: the quest line starts fresh and the intro is skipped.
- `SaveManager.load_game()` applies the quest data straight away (QuestManager is an autoload, so it survives the scene reload). A death restart keeps the quest state in memory.
- `SaveManager.reset_runtime_state()` (the pause menu's Restart) also resets the quests and world flags.
- Bad save data is sanitised: wrong types, non-string ids, oversized lists and unknown quests are dropped; a quest whose objective list changed since the save restarts cleanly.

## Adding a quest

1. Create a `.tres` quest resource in the region's folder under `resources/quests/` (see the existing ones) and add its path to `QuestManager.QUEST_PATHS`.
2. Set `prerequisites` and point a previous quest's `next_quest` at it.
3. Use existing item ids for rewards; `QuestData.validate()` rejects unknown items.
4. Run `tests/quest_check.gd`.

## Not verified here

- The visual look and timing of the opening and the ending screen (only structure, pausing and skipping were run).
- Audio: the opening plays the existing `hit_heavy` sound as a thunder crack, nothing more.
