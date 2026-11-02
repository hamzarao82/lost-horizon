# Quests, quest items and the power puzzle (Milestone 3, steps 4-5)

## The First Signal (MAIN, `resources/quests/first_signal.tres`)
Nine required objectives plus one optional. Every objective listens for a game event, so order does not matter: events seen early are remembered (`QuestManager._history` for set types, `WorldState` flags for flag objectives).

| # | Objective | Event it listens for |
|---|---|---|
| 1 | Reach the outer perimeter | `WorldState.area_entered(&"area_a_perimeter")` |
| 2 | Investigate the abandoned checkpoint | `WorldState.interacted(&"checkpoint_desk")` |
| 3 | Find the source of the transmission | `WorldState.interacted(&"radio")` |
| 4 | Eliminate the hostile soldiers (4) | `Enemy.defeated` (any enemy, each counted once) |
| 5 | Locate the security access card | flag `has_access_card` |
| 6 | Restore power to the communications facility | flag `comms_power_on` (set by `SequencePuzzle`) |
| 7 | Access the military terminal | `interacted(&"military_terminal")` |
| 8 | Discover the restricted research facility | `area_entered(&"area_c_research")` |
| 9 | Unlock the next mission location | flag `next_location_unlocked` (the manager sets it when the terminal is used) |
| opt | Find the missing security log | `interacted(&"log_missing_security")` or flag `doc_log_missing_security_found` |

Completing it grants the Combat Knife once, shows the MISSION COMPLETE banner (`show_mission_banner`), and starts `restore_power` (the Milestone 1 chapters `restore_power` -> `broken_perimeter` -> `final_transmission` follow unchanged).

## Data additions
- `ObjectiveData`: `optional`, `hidden_until` (flag), `Type.DISCOVER` (appended last, so saved resources keep their numbers).
- `QuestData`: `category` (MAIN / SIDE / EXPLORATION), `location_hint`, `show_mission_banner`, `required_indices()`. A quest whose objectives are all optional is invalid. Optional objectives never block completion.
- `QuestManager`: `tracker_optional()` (first visible unfinished optional objective), `add_quest_item()`, `has_quest_item()`, signal `quest_item_added`.
- Flags named `doc_<id>_found` count as discovering/interacting with `<id>` (lore documents).

## Quest items
`QuestItems` (inside `QuestManager.quest_items`) is separate from the inventory: equipping, replacing or dropping gear never removes one. Ids are stable strings, each granted once, saved in the quest data as the optional `quest_items` field (old saves without it still load; `QuestState.sanitize` drops wrong types and oversized lists). The access card (`access_card`) is granted when flag `has_access_card` becomes true, and re-granted after a load if the restored world already has the flag.

## SequencePuzzle (`scripts/world/puzzle/sequence_puzzle.gd`)
Order from `resources/puzzles/power_sequence.tres`: `power_switch_b`, `power_switch_a`, `power_switch_c`. Switch objects call `try_press(id) -> bool`:
- Not ready (flag `panel_inspected` unset): returns false, emits `hint(text)`.
- Correct next switch: sets `puzzle_power_step_<n>`, emits `step_advanced`; the last one sets `comms_power_on` and emits `solved`.
- A switch already set correctly earlier: ignored (no reset).
- Any other id: resets progress, emits `wrong_order` (plays the `hurt` sound if AudioManager exists). Never errors.
- Progress lives in `WorldState` flags (`puzzle_power_step_1..3`), so it survives a scene reload and is saved with the world.
Use `SequencePuzzle.ensure(parent)` to find or create the node (group `sequence_puzzle`). The clue for the order belongs in the lore document `log_sequence` (placed by the world scenes).

## HUD (additive)
- Optional-objective line under the tracker (dim gold, one line; included in the tracker rectangle returned by `Hud.layout_story`).
- `Hud.show_location(name)` + id -> name table (`area_a_perimeter` Outer Perimeter, `area_b_compound` Military Compound, `area_c_research` Research Access Facility, `area_d_command` Command Center); it listens to `WorldState.area_entered`, never repeats the same area twice in a row, and is skipped on very short screens.
- MISSION COMPLETE banner for quests with `show_mission_banner`; QUEST COMPLETE for the rest.
- Toast "Quest item: Security Access Card".

## Tests
`tests/quest_chain_check.gd` (48), `tests/puzzle_check.gd` (27); `tests/quest_check.gd` now finishes quest 1 through the helper `_finish_first_signal` (the old one-event "radio" quest no longer exists).
