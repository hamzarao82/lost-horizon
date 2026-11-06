# Milestone 006: Core Gameplay Systems and Player Progression

Status date: 2026-11-06. Legend: **Implemented**, **Partial**, **Documented only**, **Verified** (an automated test or screenshot was actually run), **Not tested**.

## 1. Scope (from the brief)
Inventory, equipment slots, loot and rarity, XP and levels, attributes, skills, consumables, crafting, equipment upgrading, currency and merchants, save integration, RPG screens, combat/damage integration, tests.

## 2. What already existed (audited before building)
Inventory with equipment slots for one weapon and one armor, `ItemData` and `LootTable` resources, enemy and crate drops, guaranteed Warden loot, medkits (the only healing path), teleport charges, armor pool, equipment screen, save v2 with checkpoints. These are extended, not replaced.

## 3. Architecture decisions
- One new autoload, `Progression`, owns XP, level, attribute points, skill ranks and currency state. Everything else is `Resource` data and `RefCounted` logic.
- The `Inventory` stays the owner of items, equipment, currency and claimed unique rewards. `Inventory.stat_totals()` returns exactly `damage_mult`, `damage_reduction`, `max_health_bonus`, `move_speed_mult`; the damage pipeline reads these and nothing else from equipment.
- One damage pipeline (`StatsResolver`): base weapon damage times attribute, skill and equipment multipliers, each applied once, then armor reduction. Level-1 values equal today's numbers, so the early game is not stronger.
- Data-driven definitions: items, loot tables, recipes, merchants, attributes, skills and the XP curve are `.tres` resources; no item-specific logic in gameplay scripts.
- Save: each part exposes `to_dict` and `from_dict` with validation; one later step integrates them as save version 3 with migration from version 2.

## 4. Work phases
| Phase | Content | Status |
|---|---|---|
| 1a | Progression: XP curve, attributes, skills, damage pipeline | done, verified by tests |
| 1b | Items: item data, inventory, slots, loot, crafting, upgrading, merchant, icons | done, verified by tests |
| 2a | Save v3, migration from v2 | done, verified by tests |
| 2b | Screens | done, tested, screenshots of five screens |
| 3 | In-world integration (merchant placed, XP and loot hooks, balance pass), screenshots, performance check | not started |

## 5. Acceptance status (all **not yet verified** until phase results are checked)
Every item in the brief's test list (inventory, equipment, loot, progression, crafting and economy, save, combat) is open. This table will be filled with real test names and counts when each phase completes; a feature is not marked complete because a script exists.

## 6. Known risks
- Balance has no human playtest; numbers come from formulas and tests only.
- Visual equipment attachment on the skeleton (head, gloves, legs) needs models that do not exist; only weapon and body armor have models.
- Skill and attribute effects that touch dodge, teleport and movement are small additive hooks and need play feel testing.
- The Milestone 5 gaps remain: human play-through, Android device run, desktop frame rate at High quality, web load time.

## 7. Status after phases 1 and 2 (2026-11-06)
All 43 suites pass on the merged `master`, with zero script errors, after the fixes listed below. New suites: progression_check 74, skills_check 33, damage_pipeline_check 54, gear_integration_check 6, currency_single_owner_check 9, items_inventory_check 64, items_equipment_check 46, items_loot_check 35, items_economy_check 47, save_v3_check 56, world_progression_check 32, rpg_screens_check 105.

| Area | Status |
|---|---|
| XP, levels, attributes, 12 skills, damage pipeline | Implemented, **verified** by tests (level 1 equals the old numbers; each modifier applied once) |
| Inventory (40 stacks, categories, rarity, sort, filter, protection of quest and unique items) | Implemented, **verified** by tests |
| Equipment slots (weapon, secondary, head, body, gloves, legs, accessory), compare, stat totals | Implemented, **verified** by tests; worn gear has no model on the character |
| Loot tables, rarity, unique rewards once | Implemented, **verified** by tests with seeded RNG; wired to enemies, crates, Warden, mission reward |
| Crafting (6 recipes), upgrading (cap 5, Warden's Cleaver own curve) | Implemented, **verified** by tests |
| Merchant (service, placed quartermaster in Area B, trading screen) | Implemented; buy/sell **verified** through the service and the screen test; the quartermaster's stall has no character model and was never seen in a screenshot |
| Save v3 with migration from a Milestone 5 save | Implemented, **verified** by tests (fixture v2 save loads at level 1 with its gear intact; hostile data loads safely) |
| Screens: inventory, character and skill tree, crafting, merchant, notifications | Implemented, **verified** by tests; five screenshots of the real game were looked at; upgrade dialog, level-up banner and loot toasts were not captured |
| Combo extension and counterattack skills | **Not implemented** |
| Temporary buffs beyond sharpening oil; enemy scaling | Configuration only, unused |
| Balance, feel, controller and touch use of the screens | **Not tested** by a person or on a device |

**Bugs found and fixed while merging:** (1) the weapon damage multiplier was applied twice (a 2.1x claymore hit for 4.4x), now guarded by `gear_integration_check`; (2) two separate currency balances, now one owner (the Inventory) guarded by `currency_single_owner_check`; (3) the playthrough bot crashed on a freed pickup once the new loot tables created more pickups (test loop made robust).

**Known gaps:** elite and heavy enemies now have about a 4.3% chance per kill to drop boots or gloves; `Inventory.collect()` does not emit the item-collected signal so crafted and bought items show no toast; death reload keeping progression is tested through a respawned scene, not the real 2 s death timer; Android and web storage not run.

**Web load after Milestone 6 (boot probe, desktop Chromium, one run):** reveal done at 41.8 s game clock, against 37.0 s for the previous live build and 27.7 s for the Milestone 4 build. The budget is 30 s: **missed**, and it has grown with each milestone since Milestone 4. Pack 9.7 MB, wasm 39.5 MB. The cause of the growth has not been investigated.
