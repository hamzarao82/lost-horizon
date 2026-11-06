# Items, Inventory, Loot, Crafting, Upgrades and Merchants (Milestone 6, items track)

Status legend: **V** verified by a test that was run; **P** partly implemented; **D** documented only; **N** not tested.

## 1. What exists

| Area | Status | Where | Test |
|---|---|---|---|
| Item definitions (category, slot, stack size, stats, rarity, unique, value, currency, effect, icon) | V | `scripts/inventory/item_data.gd`, `resources/items/*.tres` (32 items) | `items_equipment_check` data rules, `equipment_check` (old items still load) |
| Bag: stacking, capacity 40 stacks, overflow, remove, drop, sort, filter | V | `scripts/inventory/inventory.gd` | `items_inventory_check` (64) |
| Quest and unique items cannot be dropped or sold | V | `ItemData.is_protected()` | `items_inventory_check`, `items_economy_check` |
| Equipment slots: primary weapon, secondary weapon, head, body, gloves, legs, accessory | V (logic) | `Inventory.equip/unequip/equipped` | `items_equipment_check` (46) |
| Comparison (`compare(a, b)` stat deltas) and `stat_totals()` | V | `Inventory` | `items_equipment_check` |
| Consumables: heal, armor restore, timed buff, teleport charge; cooldowns | V (heal, armor, buff); P (teleport charge: no test with the real Teleport autoload) | `Inventory.use_item` | `items_inventory_check` |
| Loot tables: weights, guaranteed entries, rolls, rarity weights, stack counts, source and region tags | V | `scripts/loot/loot_table.gd` (`roll()` unchanged), `LootService` | `items_loot_check` (35) |
| Unique-reward protection across save/load | V | `Inventory.unique_claimed` | `items_loot_check` |
| Crafting: 6 recipes, atomic craft, currency cost | V | `scripts/items/recipe.gd`, `crafting_book.gd`, `resources/recipes/` | `items_economy_check` (47) |
| Upgrading: preview, apply, costs, cap, unique curve | V | `scripts/items/upgrade_service.gd` | `items_economy_check`, `items_equipment_check` |
| Merchant: stock, buy, sell, persistence, no buy-sell loop | V | `scripts/items/merchant_data.gd`, `merchant_service.gd`, `resources/merchants/outpost_quartermaster.tres` | `items_economy_check` |
| Merchant interactable node | P (script only; no scene placed in the world, no trading screen) | `scripts/items/merchant.gd` | not tested |
| Icons | V (files exist and load); N (never viewed in a UI) | `tools/gen_icons.gd` -> `assets/icons/*.png` | `items_equipment_check` |
| Save round trip and old-format loading of the inventory dictionary | V | `Inventory.to_dict/from_dict/sanitize` | `items_inventory_check` |

## 2. Known gaps (not done)
- **SaveManager strips the new fields.** `SaveManager` rebuilds the inventory dictionary with only `weapon`, `armor`, `armor_points`, `potions` when it sanitizes a save, so the bag, currency, upgrades, worn gear, unique-claimed list and merchant stock are **not persisted through the real save file yet**. `Inventory.to_dict()` and `from_dict()` work and are tested directly. The save layer must pass the extra keys through `Inventory.sanitize(raw)` (provided for that, tested) and bump its version. This track did not edit `save_manager.gd` by instruction.
- No inventory, equipment, crafting, upgrade or merchant **screens**; no loot notification UI. The older `EquipmentScreen` is untouched.
- Existing enemies and crates still use their old tables (`roll()` and `loot_paths`). The new tables (`enemy_*`, `crate_*`, `reward_first_signal`) and `LootService.grant()` are not wired into the world, the Warden or the mission reward.
- The `max_health_bonus`, `damage_reduction` and `move_speed_mult` totals are computed but nothing in the player or damage code reads them yet (the progression track owns that).
- Worn gear is not shown on the player model (no helmet, glove or boot meshes exist).
- Rarity does not scale item stats automatically: every item's numbers are authored, and `RarityTable` sets the allowed ranges, sell multipliers and weights. A test only checks the caps on wearable gear and that legendary items are unique.
- A merchant node has not been placed in Outpost 17.

## 3. Rules and data

**Ownership.** `Inventory` owns currency (`currency`, `add_currency`, `spend_currency`), the bag, upgrade levels and the unique-claimed set. Items are shared `Resource`s and are never modified; upgrade levels live in `Inventory.upgrades[item_id]`. Another system that wants to show currency should read the inventory.

**One copy of each piece of equipment.** Equipment stacks to 1 and a second copy is refused (`collect` returns overflow, `add_item` leaves it on the ground). A worn piece is never also in the bag.

**Old pickup rules are kept.** Weapons and body armor still auto-equip only when better; the replaced piece now goes to the bag instead of vanishing. Gloves, helmets, boots, accessories and secondary weapons auto-equip into an empty slot or when better. Medkits (`health_potion`) still live in `Inventory.potions`; all healing, including bandages, goes through `HealthComponent.heal`.

**Damage pipeline contract.** `stat_totals()` returns exactly `damage_mult`, `damage_reduction` (0 to 0.5), `max_health_bonus` and `move_speed_mult` (0.85 to 1.2). `damage_multiplier()` equals `stat_totals().damage_mult`, so a damage pipeline must use one or the other, not both. `damage_reduction()` (the old method) still returns 0.0 because armor is a bar.

**Rarity** (`RarityTable`): stat range at most +20% for legendary, sell multipliers 0.4 / 0.5 / 0.6 / 0.75 / 1.0, default drop weights 60 / 25 / 10 / 4 / 1.

**Upgrade curve** (`UpgradeService`): primary weapon damage +4% of base per level, body armor points +6%, other gear +8% of each bonus, cap 5 levels (+20% weapon damage, +30% armor). Cost for level n to n+1: one kit times (n+1) plus `40 x (n+1) x rarity cost multiplier` credits. The Warden's Cleaver uses its own curve (`UNIQUE_CURVES`): +0.06, +0.06 and attack speed +0.03, +0.06 and damage reduction +0.02, +0.08, +0.10 and attack speed +0.03. Total +0.36 damage (about +15.6%, less than the generic +20%), +0.06 attack speed, +2% damage reduction, and it needs 2 salvaged electronics per level on top of the kit.

**Merchant.** Prices are authored per stock entry; the vendor pays `value x sell_multiplier x rarity multiplier` (a test checks every stock item sells for more than it buys back). Stock that has been bought is stored in `Inventory.merchant_stock`.

**Recipes** (`resources/recipes/`): bandage (2 cloth), medkit supply (3 cloth + 1 antiseptic), armor patch (3 scrap + 1 cloth), sharpening oil (1 antiseptic + 1 scrap), weapon upgrade kit (4 scrap + 1 electronics + 20 credits), armor upgrade kit (3 scrap + 2 cloth + 20 credits).

**Regenerating data.** `godot --headless --path . -s tools/gen_items.gd` rewrites the Milestone 6 items, recipes, loot tables and merchant (existing items are never touched). `tools/gen_icons.gd` redraws every icon.

## World wiring (Milestone 6 phase 2)
Verified by `tests/world_progression_check.gd` (32 checks).

| Source | What drops | Rate |
|---|---|---|
| Soldier (regular) | its existing gear table (`soldier_loot`, unchanged) plus `enemy_regular`: scrap, cloth, small credits, bandage | gear 70% as before; bonus 35% (measured 4000 seeded rolls) |
| Hunter and heavy (elite) | their existing tables plus `enemy_elite` (scrap, credits, armor patch, antiseptic, field boots, tactical gloves, weapon kit) | bonus drop chance from the table; about 4.3% per kill is wearable gear (boots or gloves), a small addition to elite gear drops |
| Warden (boss) | unchanged guaranteed table; blade and plate are unique and never given twice | guaranteed |
| Supply crates | their fixed items plus `crate_common` once, at opening | one roll; the crate is one-shot through its world flag |
| Hidden caches (`cache_*`) | fixed items plus `crate_hidden` | same |
| Mission `first_signal` | `reward_first_signal`: 60 credits, weapon upgrade kit, intel drive | once, guarded by the saved flag `mission_reward_granted` |

The quartermaster (`outpost_quartermaster`, from `resources/merchants`) stands at the compound gate in Area B (about x -14, z 24) behind a plain supply table. Interacting emits `MerchantNpc.open_requested(merchant_data)` (and the older `trade_requested`); no trading screen exists yet, that is the UI work. Purchases and the remaining stock persist through save and load (verified).

Field Medic: `Inventory.use_potion` heals `potion_heal x Progression.heal_multiplier()`; 1.0 without the skill (verified: 40 vs 44 with rank 1).
