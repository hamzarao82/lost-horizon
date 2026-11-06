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
| 1a | Progression: XP curve, attributes, skills, damage pipeline, tests, `PROGRESSION_SYSTEM.md` | in progress (agent), **not verified** |
| 1b | Items: item data, inventory, slots, loot, crafting, upgrading, merchant logic, icons, tests, `ITEMS_AND_ECONOMY.md` | in progress (agent), **not verified** |
| 2a | Save v3, migration from v2, test loading a Milestone 5 save | not started |
| 2b | Screens: inventory, character/skills, crafting/upgrade, merchant, loot and level-up notices | not started |
| 3 | In-world integration (merchant placed, XP and loot hooks, balance pass), screenshots, performance check | not started |

## 5. Acceptance status (all **not yet verified** until phase results are checked)
Every item in the brief's test list (inventory, equipment, loot, progression, crafting and economy, save, combat) is open. This table will be filled with real test names and counts when each phase completes; a feature is not marked complete because a script exists.

## 6. Known risks
- Balance has no human playtest; numbers come from formulas and tests only.
- Visual equipment attachment on the skeleton (head, gloves, legs) needs models that do not exist; only weapon and body armor have models.
- Skill and attribute effects that touch dodge, teleport and movement are small additive hooks and need play feel testing.
- The Milestone 5 gaps remain: human play-through, Android device run, desktop frame rate at High quality, web load time.
