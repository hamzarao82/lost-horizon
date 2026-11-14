# Combat balance (Milestone 11)

**What this is:** numbers computed by `tests/balance_sim_check.gd` from the real resources (enemy scenes, `EnemyConfig`, `FacilityEnemyConfig`, attack data, the level scaling config, the weapon items, `Inventory`'s damage pipeline). **These are bot and formula numbers, not a human playtest.** They measure time to kill and damage per hit; they cannot say whether a fight is fun, readable or fair to a real hand. A tester should treat them as a map of where to look first.

The test also fails when this document's Iron Fortress numbers drift from the data, so a change to any enemy has to refresh this file.

## Assumptions (all visible in `scripts/balance/balance_table.gd`)
- The expected player level per region is **an assumption**: Outpost 17 = 1, Dead Coast = 3, Blackwood = 5, Research Complex = 7, Iron Fortress = 9. Nothing in the game fixes these.
- The player has no attribute or skill investment (damage part 1.0) and every weapon is at upgrade level 0.
- Time to kill assumes the three-hit light chain, every swing lands, full recovery between swings, no dodging and no knockback loss. A real fight is slower. Heavy, sprint, air and spin attacks are not modelled.
- Enemy health and damage use `EnemyScaling` at that level. Only the Warden is treated as a "boss" by that code (`enemy is Warden`), so every other boss scales like an ordinary enemy.
- EHP = health + armor pool. Enemy damage per second = hit damage / (swing frames + the mean of its cooldown range); ranged enemies use their burst if higher. Bosses use the mean over their own attack set (`BOSS_ATTACKS`), not the single swing in their config.
- "Threat" = (wave EHP + boss EHP) x (wave DPS + boss DPS) / 1000. It is a ranking device, not a unit.
- Wave tables are the real stage and arena wave files. Free-roaming patrols are not counted.

## Region table

| Region | Player level | Waves | Wave EHP | Wave DPS | Boss EHP | Boss DPS | Threat |
|---|---|---|---|---|---|---|---|
| Outpost 17 | 1 | 5 | 760 | 64.5 | 420 | 4.4 | 81.3 |
| Dead Coast | 3 | 3 | 637 | 51.0 | 932 | 12.3 | 99.3 |
| Blackwood | 5 | 3 | 788 | 59.2 | 1028 | 12.7 | 130.6 |
| Research Complex | 7 | 3 | 1215 | 69.6 | 923 | 13.6 | 177.7 |
| Iron Fortress | 9 | 4 | 2664 | 93.3 | 1347 | 10.5 | 416.5 |

## Enemies and bosses (stats at the region's expected level)

| Region | Enemy | Count in waves | EHP | Hit | DPS | Detection | Hits to kill player |
|---|---|---|---|---|---|---|---|
| Outpost 17 | Soldier | 5 | 60 | 12.0 | 4.8 | 14 m | 9 |
| Outpost 17 | Hunter | 4 | 45 | 9.0 | 6.7 | 14 m | 12 |
| Outpost 17 | Heavy | 2 | 140 | 24.0 | 6.9 | 14 m | 5 |
| Outpost 17 | **The Warden** (boss) | - | 420 | 22.0 | 4.4 | 60 m | 5 |
| Dead Coast | Soldier | 6 | 65 | 12.5 | 5.0 | 14 m | 9 |
| Dead Coast | Hunter | 2 | 49 | 9.4 | 6.9 | 14 m | 11 |
| Dead Coast | Heavy | 1 | 151 | 25.0 | 7.2 | 14 m | 5 |
| Dead Coast | **Harbor Commander** (boss) | - | 407 | 20.8 | 6.1 | 18 m | 5 |
| Dead Coast | **Cove Boss** (boss) | - | 524 | 20.8 | 6.1 | 18 m | 5 |
| Blackwood | Soldier | 6 | 70 | 13.0 | 5.2 | 14 m | 8 |
| Blackwood | Hunter | 3 | 52 | 9.7 | 7.2 | 14 m | 11 |
| Blackwood | Elite Security Soldier | 1 | 214 | 10.8 | 6.5 | 18 m | 10 |
| Blackwood | **Patrol Chief** (boss) | - | 436 | 21.6 | 6.4 | 18 m | 5 |
| Blackwood | **Site Overseer** (boss) | - | 592 | 21.6 | 6.4 | 18 m | 5 |
| Research Complex | Security Guard | 5 | 87 | 13.4 | 5.4 | 14 m | 8 |
| Research Complex | Subject | 5 | 112 | 15.7 | 7.0 | 9 m | 7 |
| Research Complex | Heavy Facility Guard | 1 | 223 | 26.9 | 7.8 | 12 m | 4 |
| Research Complex | **Subject Zero** (boss) | - | 372 | 22.4 | 6.6 | 18 m | 5 |
| Research Complex | **Facility Commander** (boss) | - | 551 | 10.1 | 7.0 | 16 m | 10 |
| Iron Fortress | Fortress Infantry | 7 | 145 | 11.6 | 7.0 | 18 m | 9 |
| Iron Fortress | Elite Security Soldier | 4 | 238 | 11.6 | 7.0 | 18 m | 9 |
| Iron Fortress | Heavy Assault Unit | 1 | 433 | 27.8 | 9.8 | 18 m | 4 |
| Iron Fortress | Tactical Commander | 1 | 261 | 11.6 | 7.0 | 18 m | 9 |
| Iron Fortress | **Fortress Captain** (boss) | - | 555 | 23.2 | 6.1 | 18 m | 5 |
| Iron Fortress | **The Director** (boss) | - | 792 | 18.6 | 4.4 | 18 m | 6 |

## Weapons: the three-hit light chain

| Weapon | Chain seconds | Chain damage | DPS |
|---|---|---|---|
| Wooden Stick | 1.12 | 37.0 | 33.1 |
| Improvised Blade | 1.12 | 37.0 | 33.1 |
| Combat Knife | 0.87 | 46.3 | 53.2 |
| Iron Sword | 1.12 | 50.0 | 44.7 |
| Military Machete | 1.12 | 55.5 | 49.7 |
| Katana | 0.94 | 64.8 | 68.9 |
| Tactical Sword | 1.12 | 70.3 | 63.0 |
| Claymore | 1.43 | 77.7 | 54.3 |
| Warden's Cleaver | 1.23 | 85.1 | 69.3 |

## Time to kill (seconds, light chain, every swing lands)

| Weapon | Outpost 17 Soldier (60) | Outpost 17 Heavy (140) | Outpost 17 The Warden (420) | Research Complex Heavy Facility Guard (223) | Iron Fortress Heavy Assault Unit (433) | Iron Fortress Fortress Captain (555) | Iron Fortress The Director (792) |
|---|---|---|---|---|---|---|---|
| Wooden Stick | 1.8 | 4.2 | 12.7 | 6.7 | 13.1 | 16.8 | 23.9 |
| Improvised Blade | 1.8 | 4.2 | 12.7 | 6.7 | 13.1 | 16.8 | 23.9 |
| Combat Knife | 1.1 | 2.6 | 7.9 | 4.2 | 8.1 | 10.4 | 14.9 |
| Iron Sword | 1.3 | 3.1 | 9.4 | 5.0 | 9.7 | 12.4 | 17.7 |
| Military Machete | 1.2 | 2.8 | 8.5 | 4.5 | 8.7 | 11.2 | 15.9 |
| Katana | 0.9 | 2.0 | 6.1 | 3.2 | 6.3 | 8.1 | 11.5 |
| Tactical Sword | 1.0 | 2.2 | 6.7 | 3.5 | 6.9 | 8.8 | 12.6 |
| Claymore | 1.1 | 2.6 | 7.7 | 4.1 | 8.0 | 10.2 | 14.6 |
| Warden's Cleaver | 0.9 | 2.0 | 6.1 | 3.2 | 6.3 | 8.0 | 11.4 |

## What the numbers say (honestly)
- **The Iron Fortress is the hardest region by data, by a wide margin:** threat 416.5 against 177.7 for the next region (Research Complex), with the most wave health (2664), the most wave damage per second (93.3) and the most boss health (1347). It is hard through health and numbers more than behaviour; the ranged pressure, defensive guards and reinforcement calls the M11 plan describes do not exist yet.
- **Difficulty rises every region** (81.3, 99.3, 130.6, 177.7, 416.5), but the step into the Fortress is more than twice the previous step, while the earlier steps are gentle. Dead Coast's three waves (637 health) are lighter than Outpost 17's arena (760), the only dip.
- **Boss health does not rise steadily:** Research Complex bosses total 923, below Blackwood's 1028. This is because Subject Zero (372 at level 7) is the weakest named boss after the Warden's 420.
- **The Director is not the highest-damage boss:** his mean damage per second (4.4) is the same as the Warden's, and he has 792 health. His difficulty is meant to come from his phases and ranged patterns, which these numbers do not capture.
- **Only the Heavy Assault Unit (27.8) and Heavy Facility Guard (26.9) hit for more than a quarter of the player's health**; the player survives at least 4 hits from anything. Nothing one-shots a player at full health.
- **The Claymore is barely better than the Combat Knife per second (54.3 vs 53.2):** its 2.1 damage multiplier is paid back by an 0.85 attack speed and, since Milestone 11, a 1.15 recovery scale. It hits harder per swing and staggers more (stagger 1.5), which this DPS table does not credit. The Katana (68.9) and the Warden's Cleaver (69.3) are the best chains.
- **The starting blade and the wooden stick are identical** (33.1 DPS).

## Weapon identity (Milestone 11)
Each weapon now carries `stagger_power`, `recovery_scale` and `heavy_multiplier` (`scripts/inventory/item_data.gd`, neutral at 1.0). `WeaponProfiles.scaled()` turns the base attack into the one the player actually uses; a neutral weapon returns the same object, so the starting blade, the stick and the Machete behave exactly as before.

| Weapon | Reach | Stagger power | Recovery scale | Heavy multiplier |
|---|---|---|---|---|
| Combat Knife | 0.7 | 0.60 | 0.80 | 0.90 |
| Katana | 1.1 | 0.85 | 0.85 | 1.00 |
| Improvised Blade / Wooden Stick / Military Machete | 0.9 / 0.9 / 1.0 | 1.00 | 1.00 | 1.00 |
| Iron Sword | 1.0 | 1.10 | 1.00 | 1.05 |
| Tactical Sword | 1.1 | 1.15 | 1.00 | 1.10 |
| Claymore | 1.3 | 1.50 | 1.15 | 1.30 |
| Warden's Cleaver | 1.4 | 1.60 | 1.10 | 1.35 |

**Limits:** `reach` is still only the visual length of the weapon model (the hitbox belongs to the player scene), so it has no gameplay effect. The skinned visuals read the base attack's recovery frames, so for a weapon with a recovery scale other than 1.0 the animation and the real recovery differ slightly. Stagger applies to enemies that are staggerable at all; high `stagger_resist` bosses ignore most of it. Nothing here has been felt by a person.

## Boss fairness
`tests/boss_fairness_check.gd` reads every attack of the Warden, Subject Zero, the Facility Commander, the Fortress Captain and the Director. All obey the rule (telegraph at least 0.6 s, punish window at least 0.5 s, rushes and dashes at least 0.8 s, no hit above 25 damage, one hit per target per swing) **except three documented attacks**: the Warden's flurry (14-frame telegraph, a chained follow-up to the slam), the Warden's shockwave (an effect the slam spawns, not an attack of its own) and the Facility Commander's close-range shove (28-frame, 0.47 s telegraph, below the 0.6 s rule; `ranged_check` only requires 0.4 s). These are listed by name in the test and fail it if they are fixed silently.

## Update (2026-11-14)
`warden_flurry` telegraph/recovery 14/20 -> 36/30 frames and `ranged_shove` telegraph 28 -> 36 frames, so every boss attack meets the 0.6 s / 0.5 s rule. Damage values are unchanged, so the time-to-kill numbers above are unaffected.
