# Progression and Balancing

Tags are explained in [MILESTONE_004.md](MILESTONE_004.md). All numbers below were read from the resource files on the `milestone-003` branch. Anything marked `[PROPOSED]` is **not** a confirmed change and nothing is changed without approval.

## 1. Confirmed existing equipment `[IMPLEMENTED]`

### Weapons (power = damage x speed^0.5; a weapon of lower power is not picked up)
| Weapon | Rarity | Damage x | Speed | Power |
|---|---|---:|---:|---:|
| Improvised Blade (start) | Common | 1.00 | 1.00 | 1.00 |
| Combat Knife | Uncommon | 1.25 | 1.15 | 1.34 |
| Iron Sword | Uncommon | 1.35 | 1.00 | 1.35 |
| Military Machete | Rare | 1.50 | 1.00 | 1.50 |
| Katana | Rare | 1.75 | 1.10 | 1.84 |
| Tactical Sword | Epic | 1.90 | 1.00 | 1.90 |
| Claymore | Epic | 2.10 | 0.85 | 1.94 |
| Warden's Cleaver | Legendary | 2.30 | 0.95 | 2.24 |

### Armor (a second health bar: damage drains it first; it never regenerates)
| Armor | Rarity | Armor points |
|---|---|---:|
| Light Tactical | Common | 30 |
| Reinforced | Uncommon | 60 |
| Heavy Combat | Rare | 100 |
| Warden Plate | Epic | 140 |

A better armor refills the bar. An **Armor Plate** restores 40 points on pickup (left on the ground when the bar is full or no armor is worn).

### Consumables and abilities
- **Medkit:** restores 40 health, key R or the Heal button, can be buffered for 0.8 s, limited only by how many are held (cap 99).
- **Teleport:** 2 charges, each recharges 10 real-time minutes (one at a time), random safe destination, 0.5 s invulnerability, persisted across sessions. See `TELEPORT.md`.
- **Player base:** 100 health, 100 stamina; dodge costs 20 stamina; attacks cost 5–30 (see `COMBAT.md`).

### Loot tables
Soldier (70% drop: medkit, knife, light armor, machete, armor plate), Hunter (85%: medkit, knife, machete, tactical sword, light armor, reinforced armor), Heavy (always: medkit, machete, reinforced armor, heavy armor, tactical sword), Warden (guaranteed signature items). Supply crates and caches use their own lists.

## 2. The first complete progression loop (target for the slice)
Intended gear at each stage of the mission (`[PROPOSED]` curve; the drop rules above already allow it, but nothing guarantees it):

| Stage | Expected gear | Source |
|---|---|---|
| Start (beach) | Improvised Blade, no armor, 0 medkits | fixed |
| After the beach crates | Iron Sword or Combat Knife, 1–2 medkits | beach crates |
| After compound combat | Machete or Reinforced Armor, 2–3 medkits | drops and crates |
| Research wing | Armor plate, Reinforced or Heavy Armor | cache `cache_c_hidden`, guard drops |
| Command center | Katana or Tactical Sword, medkits | hunters, cache `cache_d_hidden` |
| Warden | **Cleaver and Warden Plate** | guaranteed drop |

Design rule: by the Warden the player should plausibly hold a Rare weapon and a 60–100 point armor, so the signature reward feels like a clear step up (Cleaver power 2.24 vs about 1.5–1.9; Plate 140 vs 60–100).

## 3. Presentation requirements `[NEW-M4]`
- **Rarity colours** (existing palette: grey, green, blue, purple, orange) used consistently in: pickup labels, toasts, the equipment panel chip, the inventory screen and the results screen.
- **Equipment comparison:** when walking onto a weapon or armor that is *not* an upgrade, the toast already says "(not an upgrade)"; add a short comparison line ("Machete x1.50 vs Iron Sword x1.35") and, in the equipment screen, a side-by-side panel (damage, speed, power; armor points).
- **Loot feedback:** light column and sound by rarity, a short "NEW" marker on upgrades, an unmistakable flourish for the boss reward.
- **Inventory usability:** an inventory/equipment screen (pause menu tab) showing equipped weapon and armor, medkit count, quest items (access card), documents found; no drag and drop, no grid, no crafting.

## 4. Balance observations from the current data (not changes)
- **Armor vs enemy damage:** soldier 12, hunter 9, heavy 24 per hit, Warden slam 22. A 140-point Plate absorbs about 6 Warden slams; Reinforced (60) about 2–3. This makes the Plate the clearest defensive upgrade.
- **Cleaver speed 0.95** is slightly slower than most weapons; its power gain comes from damage. Combat feel with slower swings has not been human-tested `[UNVERIFIED]`.
- **Medkit economy:** soldier drops give a medkit with weight 5 of 9.5 (about 53% of drops, 37% overall); healing 40 against a 100 health pool is generous relative to the boss damage numbers. A boss fight with 3 medkits may become too easy `[UNVERIFIED]`.
- **Teleport:** 10-minute recharge means at most 2 uses in a 20–30 minute slice; it behaves as an emergency button, which matches the brief.

## 5. Proposed balance changes (each needs approval; none applied)
| # | Proposal | Reason | Risk |
|---|---|---|---|
| B1 | Cap carried medkits at 5 for the slice | keep the boss tense | feels punishing if drops are generous |
| B2 | Boss fight: block medkit use for 1 s after use (global cooldown) | stop spam-healing | UI feedback needed |
| B3 | Phase 2 threshold 40% (see boss doc) | longer phase 1 | needs boss tests updated |
| B4 | Warden signature drop: Cleaver and Plate guaranteed (already true); add a rarity "legendary" light column | feedback only, no numbers | none |
| B5 | Armor plate drop weight slightly higher in the research wing cache | supports the intended curve | balance drift |

## 6. Death, respawn and encounter reset `[IMPLEMENTED]` behaviour and `[PROPOSED]` rules
**Confirmed (`SAVE.md`):** dying outside the arena waves respawns at the last checkpoint with the gear and health the player had there; quest, puzzle and world state are kept (completed objectives never reset); doors opened stay open; killed patrol squads stay dead; unique loot never duplicates. Dying during the arena waves keeps the wave-checkpoint behaviour. The Area D boss fight restarts because the scene reloads.
**Proposed:** a short "You died" screen with the cause, the respawn location name, a one-line hint, a Continue button; no gear loss or penalty in the slice. Encounter reset rules: courtyard waves and the Warden reset; patrol squads that were not wiped out respawn at their route; caches already looted stay looted.

## 7. How balance will be measured
- A deterministic combat bot (fixed attack pattern, fixed dodge timing) fights the Warden and each wave with defined gear sets; record time to kill, damage taken, medkits used. Tests assert ranges, not exact numbers.
- Human playtests: three people, no instructions; record deaths per encounter and perceived difficulty.
- No balance change is accepted without before/after bot numbers.

## 8. Unverified
- Nobody has human-tested the pacing of drops across the whole mission.
- The loot curve in section 2 is an intention; randomness can break it (the guaranteed pieces are the Warden items and fixed crates).
