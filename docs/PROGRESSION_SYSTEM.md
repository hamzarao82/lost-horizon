# Progression System (Milestone 6, part 1: XP, attributes, skills, damage pipeline)

Status date: 2026-11-06. Legend: **Tested** = covered by a headless test that was run (see section 7); **Wired** = connected in the running game but only tested through logic; **Not done** = absent. Items, inventory UI, equipment slots, loot tables, crafting, merchants, save v3 and all screens belong to other parts of Milestone 6 and are **not** covered here.

## 1. Architecture

| File | Role |
|---|---|
| `scripts/progression/progression_config.gd` + `resources/progression/progression_config.tres` | XP curve, point grants, kill/quest/discovery XP, balance caps |
| `attribute_data.gd` + `resources/progression/attributes/*.tres` | five attributes (vitality, strength, endurance, agility, technique) |
| `skill_data.gd` + `resources/progression/skills/*.tres` | 12 skills in four categories |
| `skill_tree.gd` | prerequisites, level gate, costs, node state (LOCKED / AVAILABLE / OWNED / MAXED), validation, cycle check |
| `player_progress.gd` | pure state (XP, points, ranks, currency, discoveries) with validated `to_dict` / `from_dict` |
| `stats_resolver.gd` | the one place where state becomes gameplay numbers (static, pure) |
| `progression.gd` (autoload `Progression`) | owns the state, listens to gameplay signals, applies stats to the player |
| `tools/gen_progression_data.gd` | regenerates the `.tres` files from a readable table |

Data is Resources; no item or skill is named in gameplay code. Effect keys are a closed list in `StatsResolver.EFFECTS`; a resource using any other key fails validation.

## 2. Damage pipeline (each modifier enters once)

```
damage dealt = attack.damage
             x Inventory.damage_multiplier()                   weapon (existing, applied at the call site)
             x min(1 + damage_all + damage_<kind>, cap)        attributes + skills, additive inside
             x equipment_stats.damage_mult                     gear other than the weapon
damage taken = raw x (1 - clamp(resist + equipment_stats.damage_reduction, 0, 0.6))   then the armor pool as before
```

`kind` comes from the attack id: `light_*` = light, `heavy*` and `sprint*` = heavy, `air*` and `spin*` = special. The cap is `damage_mult_cap` = 1.6 on the progression part. The Player calls `Progression` through two additive one-line hooks (`_progression_scale`, `_incoming_scale`); at level 1 both return exactly 1.0, so early-game numbers are unchanged (tested).

`equipment_stats` is read from `Inventory.stat_totals()` when that method exists (the equipment part of the milestone supplies it); until then gear is neutral. Contract: `damage_mult` there must exclude the weapon's own multiplier, which `Inventory.damage_multiplier()` still provides, or the weapon would count twice.

## 3. Attributes (points above base 0, max 10 each, 1 point per level)

| Attribute | Effect per point | At 10 points |
|---|---|---|
| Vitality | +5 maximum health | +50 |
| Strength | +2% damage, all attacks | +20% |
| Endurance | +4 maximum stamina, +0.5% damage resistance | +40 stamina, 5% |
| Agility | +1% move speed, -1.5% dodge stamina cost | +10%, -15% |
| Technique | +1.5% heavy damage, -3% teleport recharge time | +15%, -30% |

## 4. Skills (1 skill point per level; level 2 grants the first)

Combat: Sharpened Edge (light +4%/rank, 3 ranks), Heavy Hitter (heavy +5%/rank, needs Sharpened Edge, level 3), Whirlwind (special +6%/rank, 2 ranks, cost 2, level 4). Survival: Toughness (+6 health/rank, 4), Tempered Nerves (-2% damage taken/rank, 3), Field Medic (+10% medkit healing/rank, 3). Mobility: Fleet Foot (+2% speed/rank), Light Step (-8% dodge cost/rank), Deep Lungs (+8 stamina/rank). Special: Quick Recharge (-8% teleport recharge/rank, cost 2), Focus (+10% stamina regeneration/rank), Scavenger (+10% currency earned/rank, needs Focus).

## 5. XP and levels

12 levels (`xp_to_next` = 100, 150, 220, 300, 400, 520, 660, 820, 1000, 1200, 1450; total 6820 XP). Sources: enemy kills (grunt 8, elite 14, heavy 20, boss 150), quests (200 default; `first_signal` 400, paid once and remembered), discoveries (25 per document or crate, once each). Anti-grind: kill XP falls 20% per level above the tier's recommended level (floor 10%), and repeat kills of the same enemy name shrink by 1/(1 + kills/40) (floor 30%). One boss kill plus the mission is worth about 550 XP, more than 60 grunt kills, so exploration and missions lead.

## 6. What changes in the running game

Wired in the game: max health, max stamina, stamina regeneration, walk and sprint speed, dodge cost (written onto the Player from captured base values, so reset restores the original numbers), attack damage, incoming damage, teleport recharge (the player's own TeleportAbility multiplies its base recharge; standalone instances are untouched), currency earned (Scavenger).

## 7. Tests (run on 2026-11-06)

| Suite | Checks | Covers |
|---|---:|---|
| `progression_check` | 74 | curve, level gates, points, anti-grind, save round trip, junk and cheated save data, autoload signals, quest and discovery paid once across reload, currency, real enemy kills awarding tier XP |
| `skills_check` | 33 | 12 skills load and validate, prerequisites, level gate, costs, max rank, node states, effects, cycle and unknown-effect detection |
| `damage_pipeline_check` | 54 | level 1 equals current numbers, known-number cases, caps, equipment applied once, attack kinds, real Player wiring and reset |

## 8. Not done, or not verified

- **Not done:** attribute and skill screens, level-up and XP notifications, the equipment stat contract on the Inventory side, save integration (`Progression.to_dict()` exists but is not yet written into the save file, so progress does not persist across game restarts until save v3), Field Medic's healing multiplier (exposed as `Progression.heal_multiplier()`, but the medkit code does not read it yet), combo extension and counterattack skills, enemy scaling (config values exist, default 0, nothing applies them).
- **Not verified:** how the numbers feel in play, the balance across a full campaign (only one region exists), and performance on Android and web. A mission playthrough with levelling was not done by a human.
