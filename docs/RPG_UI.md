# RPG screens (Milestone 6, phase 2: UI)

Status date: 2026-11-06. Legend: **Implemented**, **Verified** (a test or a screenshot that was actually run), **Not tested**, **Not done**.

## Screens and where they live
| Screen | Class (`scripts/ui/`) | Opens with | Status |
|---|---|---|---|
| Inventory (bag, equipped list, details, equip / unequip / use / drop / upgrade, filter, sort) | `InventoryScreen` | key I (the `equipment` action, so D-pad up too), pause menu "Inventory" | Implemented; logic **Verified** by `rpg_screens_check`; layout **Verified** by screenshot |
| Item details with comparison deltas (green better, red worse) | `ItemDetailsPanel` | inside Inventory and Merchant | Implemented; **Verified** (test + screenshot) |
| Upgrade preview with confirmation | inside `InventoryScreen` | "Upgrade" button | Implemented; preview equals the applied result **Verified** by test; no screenshot of the dialog |
| Character (level, XP bar, derived stats, attribute points, skill tree) | `CharacterScreen` | key K, pause menu "Character" | Implemented; **Verified** (test + screenshot) |
| Crafting | `CraftingScreen` | pause menu "Crafting" | Implemented; **Verified** (test + screenshot) |
| Merchant (buy / sell, quantity) | `MerchantScreen` | `MerchantNpc.trade_requested` signal or `PauseMenu.show_merchant(data)` | Implemented; **Verified** with the real `MerchantService`; **no merchant is placed in the world yet** |
| Loot toasts, level-up banner, credit changes | `RpgNotifications` | automatic, owned by the pause menu | Implemented; fires once per event **Verified** by test; level-up banner not seen on screen |
| Old gear overview | `EquipmentScreen` | pause menu "Gear overview", `show_equipment()` | unchanged, kept until the Inventory replaces it fully |

Shared code: `RpgScreen` (frame, pause-while-open, close on `pause` / `ui_cancel`, dismiss the upgrade confirmation first) and `RpgUi` (helpers: icon cache, touch buttons, stat formatting, failure texts).

## Rules the screens follow
- They only call `Inventory`, `Progression`, `UpgradeService`, `CraftingBook`, `MerchantService` and show the answer; they hold no gameplay rules.
- Rebuilt on signals (`Inventory.changed / item_changed / currency_changed`, Progression signals), never per frame. Icons are loaded once into a cache.
- Quest and unique items: the Drop button is disabled and the service refuses anyway.
- Buttons are at least 56 px tall; the content area scrolls, so the panel always fits.

## Test results (`tests/rpg_screens_check.gd`, headless, 105 checks, 0 failed)
Covers: notifications (one toast per pickup / credit change / level-up, rare and epic emphasis, toast cap, real `Progression.level_up`), inventory (rows, filter, details with a positive damage delta, Equip raises the damage total, quest item cannot be dropped, Drop, Use heals the real player, Sort, focus lands inside the screen, upgrade preview then Cancel spends nothing then Confirm equals the preview and costs exactly the preview), character (spend an attribute point, locked skill refuses and explains why, available skill unlocks and costs points), crafting (disabled without materials, consumes exactly the inputs, produces the output), merchant (buy 3 costs exactly 3 x price, no credits changes nothing, sell pays less than buy, quest items not offered), layout (literal 1280x720, 1600x720 and 800x360 with content scaling off: the panel fits, buttons >= 56 px, no overlapping sibling buttons).

## Screenshots (windowed, real `Main` scene, seeded inventory and points)
Inventory list, weapon comparison (claymore vs improvised blade: `x2.10 +1.10` green, `x0.85 -0.15` red), skill tree with states and prerequisite lines, crafting, merchant. Defects found in the first captures and fixed: stat values wrapping one character per line, the pause menu text showing through the translucent panel, an invisible XP bar fill.

## Known gaps
- Keyboard/gamepad navigation uses Godot's default focus order; only the initial focus is tested, not a full pad walk-through. Not tested on a real controller or on a touch device.
- The upgrade confirmation, level-up banner and loot toasts were not captured on screen.
- `Inventory.collect()` (used by crafting, merchants and loot services) does **not** emit `item_collected`, only the world pickup path `add_item()` does, so items granted through `collect()` show no loot toast until that is emitted.
- Two currency stores exist: `Inventory.currency` (used by every screen here) and `Progression.progress.currency`; they are not synchronised.
- Equipped items are listed by name; there is no character preview model and worn gear is not shown on the model.
- Layout was tested headless and at 1280x720 on screen; 800x360 and 1600x720 were not captured as screenshots.
- No merchant NPC is placed in Outpost 17 and the save file does not store the new state (phase 2 save work).

## Worn gear, the quartermaster and loot toasts (Milestone 6 visuals)
- **Worn gear:** `scripts/visual/gear_visuals.gd` shows helmet, gloves and boots on the player skeleton through five `WeaponSocket` bone attachments (`Gear_head_Head`, `Gear_gloves_Hand_R/L`, `Gear_legs_Foot_R/L`). One table (`GearVisuals.MODELS`) maps an item id to its model, so a new piece is one entry plus a model. The models (`combat_helmet`, `tactical_gloves`, `field_boots`, 184, 52 and 92 triangles) are generated by `tools/blender/make_gear.py`. Verified by `gear_visual_check` (45 checks: shown when equipped, hidden when removed, per slot, no node leaks) and by screenshots of the real game. The accessory slot has no model. Dark boots on dark legs have low contrast.
- **Quartermaster:** the merchant node now spawns the existing soldier rig in an idle pose behind the stall with the helmet model, facing the arriving player. Interaction is unchanged. Seen in a screenshot. The stall itself is still a plain brown box with a sign.
- **Loot toasts:** `Inventory.collect()` now raises `item_collected` like `add_item()`. `add_item()` raises it once for the whole call (inner `collect()` calls stay quiet), and `LootService` announces the final outcome once. Verified by `rpg_toasts_check` (12 checks: collect, add_item, crafting, merchant, loot grants). The HUD's older "Picked up X" line still fires on every `item_collected` as well, so a pickup shows both that line and the new toast; this is not resolved.
