# Save format (version 3)

Status date: 2026-11-06. **Verified** = covered by `tests/save_v3_check.gd` (56 checks) unless noted. Atomic write, `.bak` of corrupt files, checkpoints and the test-mode file are unchanged from `SAVE.md`.

## Sections
| Key | Content | Owner |
|---|---|---|
| `version` | 3 | SaveManager |
| `next_wave`, `completed`, `defeated_bosses`, `player`, `world` | as version 2 | SaveManager |
| `inventory` | weapon, armor, armor_points, potions **plus** bag, slots, currency, upgrades, unique_claimed, merchant_stock | `Inventory.to_dict()` / `Inventory.sanitize()` |
| `progression` | xp, attribute and skill points, attribute and skill ranks, rewarded quests, discoveries, kill counts | `Progression.to_dict()` / `Progression.sanitize()` |
| `quests`, `stats` | optional, as before | QuestManager, RunStats |

The inventory keeps one section (not a second `inventory_full`): the old four keys stay where Milestone 5 wrote them, so an old build's keys and a new build's keys are the same object. `Progression.currency` is not used by the save layer; the inventory owns currency.

## Migration
Version 2 (Milestone 5) loads as: progression `{}` (level 1, no skills, no points), empty bag, no currency, no upgrades, no claimed unique rewards; weapon, armor, armor points, medkits, defeated bosses and quests are intact. **Verified** with a literal Milestone 5 save in the test. Versions 0 and 1 still migrate step by step.

## Validation (hostile data)
Every number and flag is read through safe conversions (`_num`, `_whole`, `_flag`) because GDScript's `int()`, `float()` and `bool()` throw on dictionaries, arrays and strings; a wrong-typed value becomes the default. This also fixed an existing weakness: a save with a string in `completed` made the old load fail. Item ids must match the id pattern and exist; unknown ids are dropped and counted (`invalid_ids_dropped`). Counts, currency, upgrade levels, stock and list lengths are clamped. Progression is rebuilt through `PlayerProgress.from_dict` (point budgets from the level) and then **skill prerequisites and minimum levels are enforced**: a skill whose prerequisite is missing is removed and its points refunded. **Verified** with oversized, negative, wrong-typed, unknown-id and unmet-prerequisite data.

## Unique rewards
`inventory.unique_claimed` is saved; `add_item` and `collect` refuse a unique item already claimed, and loot tables skip it. **Verified** across save and reload for the Warden's blade. The mission reward is guarded by the world flag `mission_reward_granted` (saved with the world flags).

## Reset and reload
`reset_runtime_state()` (new game) resets Progression to level 1. A scene reload after death keeps Progression in memory (it is an autoload) while the inventory returns to the checkpoint snapshot, as before. **Verified** with a freed and re-spawned scene; the real 2 s death timer path was not repeated for progression.

## Not covered
Equipment visuals for head, gloves and legs (no models), Android and web file storage for the new fields (the same JSON write path, not run on a device).
