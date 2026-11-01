# Story and quests

Resource-driven, event-driven quest layer plus an opening and an ending. Nothing in a scene hardcodes a quest: progress comes from gameplay events.

## The story in four quests

| # | Quest | Objectives | Reward | Unlocks |
|---|---|---|---|---|
| 1 | The First Signal | Use the emergency radio (`interacted: radio`) | Combat Knife | Restore Power |
| 2 | Restore Power | Throw three generator switches (`switch_1..3`, shown as "Switches n/3"), then the flag `power_on` | Light Tactical Armor | Broken Perimeter |
| 3 | Broken Perimeter | Enter the courtyard (`area_entered: courtyard`), clear all five waves including the Warden | 2 Medkits | The Final Transmission |
| 4 | The Final Transmission | Flag `has_keycard` (set when the Warden dies), use the command terminal (`interacted: command_terminal`) | 1 Medkit | The ending |

The radio's voice is the narrator: it tells the survivor that Outpost 17 holds what the island's secret military organisation is hiding, asks for the power to be restored, and in the last transmission uploads the personnel files and experiment records.

## Files

| File | Role |
|---|---|
| `scripts/quests/objective_data.gd` | `ObjectiveData` resource: id, text, type (INTERACT, ENTER_AREA, KILL_COUNT, WAVE_CLEARED, ITEM_COLLECTED, FLAG, BOSS_DEFEATED), targets, count, progress label |
| `scripts/quests/quest_data.gd` | `QuestData` resource: id, title, prerequisites, objectives, rewards (item ids), `next_quest`, start/complete captions, `validate()` |
| `scripts/quests/quest_manager.gd` | Autoload `QuestManager` (no `class_name`: it would clash with the autoload) |
| `scripts/quests/quest_state.gd` | `QuestState.sanitize()` for save data |
| `resources/quests/*.tres` | The four quests |
| `scripts/story/intro.gd`, `scenes/story/Intro.tscn` | Opening |
| `scripts/story/ending.gd`, `scenes/story/Ending.tscn` | Ending and credits |
| `scripts/ui/hud.gd` | Quest tracker and subtitle queue (presentation only) |
| `tests/quest_check.gd` | 125 headless checks |

## Event contract

QuestManager listens, it never calls into gameplay (apart from handing out rewards through `Player.inventory.add_item`).

| Source | Signal / hook | Becomes |
|---|---|---|
| `WorldState` autoload (WORLD agent) | `interacted(id)` | INTERACT |
| | `area_entered(id)` | ENTER_AREA |
| | `flag_changed(id, true)` | FLAG |
| `WaveManager` (found via `node_added`) | `wave_cleared(index)` | WAVE_CLEARED, progress = highest cleared wave |
| | `all_cleared` | WAVE_CLEARED with the last wave number |
| `Enemy` (via `node_added`) | `defeated` | KILL_COUNT (display name, once per enemy instance); BOSS_DEFEATED for the group `boss` (`"The Warden"` becomes `warden`) |
| `Inventory` (via `node_added`) | `item_collected(item, kept)` | ITEM_COLLECTED when kept |

The world side must therefore emit `interacted` ids `radio`, `switch_1`, `switch_2`, `switch_3`, `command_terminal`, `area_entered` id `courtyard`, and set the flag `power_on` when the three switches are done. QuestManager itself sets `has_keycard` when the Warden is defeated (and also works without WorldState).

Rules:
- **Duplicate protection.** A set objective counts each distinct target once; a kill counts once per enemy instance; a quest completes and pays out exactly once (`completed` and `_rewarded`).
- **Order independent.** Events are remembered (`_history`), so a switch thrown before the radio still counts when quest 2 begins, and a flag that is already set counts at once.
- **Rewards** go through `Inventory.add_item` (weapons and armor only equip if better; medkits stack). If no player exists at that moment they stay queued, and are saved, until one does.
- **Captions.** `start_captions` / `complete_captions` are emitted on `caption_requested` and queued by the HUD. `QuestManager.say(text, seconds)` is available to anything else that wants a subtitle line.

## Tracker and subtitles

- Tall screens: tracker (title, objective with "(Switches 1/3)") in the left column at y=205, below the bars, the teleport label and the pause button.
- Short screens (fallback; with the project's `canvas_items` + `expand` stretch a window or phone is never shorter than 720 logical pixels, so an 800x360 window is really 1600x720): top centre at y=46, hidden while the boss bar is up.
- Subtitles: bottom centre, bottom edge 120 px above the screen edge (the toast sits at 110). Up to three lines; at most 8 lines queued.
- Both labels are capped (tracker objective two lines, subtitle three) so a long text can never grow over other widgets.

## Opening and ending

- **Opening** (about 22 s): captions on black, then a slow camera push toward the survivor and the title card. Skip with any key, click, tap, gamepad button, or the Skip button (a 0.4 s grace period avoids accidental skips). The game is paused while it plays (the intro keeps running) and unpaused on exit.
- It plays only on a fresh game: not under the headless driver, not after loading a save, not after a death restart, not when quest progress exists, and only once per run (`intro_done`; a deliberate Restart or Play Again does not repeat it). Nothing in `boot.gd` changed: QuestManager notices the Player entering the tree, waits for Boot to enable Main, then adds the scene.
- **Ending:** when quest 4 completes the final transmission captions play, then a screen "Thanks for playing" with credits, **Play Again** (clears run state through `SaveManager.reset_runtime_state()`, which also restarts the quests and the world flags, then reloads) and **Quit** (hidden on web and mobile).

## Saving

- The save gains an optional `quests` field (version stays 1): active quests with progress, completed ids, rewarded ids, pending rewards, event history, `intro_done`, and the `WorldState` flags. Saves from before the quest layer load fine: the quest line starts fresh and the intro is skipped.
- `SaveManager.load_game()` applies the quest data straight away (QuestManager is an autoload, so it survives the scene reload). A death restart keeps the quest state in memory.
- `SaveManager.reset_runtime_state()` (the pause menu's Restart) also resets the quests and world flags.
- Bad save data is sanitised: wrong types, non-string ids, oversized lists and unknown quests are dropped; a quest whose objective list changed since the save restarts cleanly.

## Adding a quest

1. Create `resources/quests/<id>.tres` (see the existing ones) and add its path to `QuestManager.QUEST_PATHS`.
2. Set `prerequisites` and point a previous quest's `next_quest` at it.
3. Use existing item ids for rewards; `QuestData.validate()` rejects unknown items.
4. Run `tests/quest_check.gd`.

## Not verified here

- The visual look and timing of the opening and the ending screen (only structure, pausing and skipping were run; the intro was run once on a real display).
- Audio: the opening plays the existing `hit_heavy` sound as a thunder crack, nothing more.
- The real interactables, switches and terminal (WORLD agent); quests were driven by simulated events and by the real `WorldState` autoload.
