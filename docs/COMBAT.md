# Combat

## Attack model
Attacks are `AttackData` resources (`resources/attacks/*.tres`), timed in frames at 60 Hz:
startup (no hit) -> active (hitbox on) -> recovery (vulnerable; chain or dodge-cancel allowed).
Damage is applied only by `Hitbox` while active, once per target per activation, scaled by the attacker's `damage_scale`.

| Attack | Startup | Active | Recovery | Damage | Stamina |
|---|---:|---:|---:|---:|---:|
| light_1 | 6 | 4 | 10 | 10 | 5 |
| light_2 | 6 | 4 | 12 | 12 | 5 |
| heavy_1 | 16 | 6 | 22 | 28 | 15 |

Chain: light -> light -> heavy finisher. Heavy can be started any time (or finishes a light chain).
Input buffer 0.2 s. Dodge (0.38 s, i-frames for the first 0.18 s, 20 stamina) can cancel recovery.

## Enemies
| Type | HP | Speed | Swing (startup/dmg) | Notes |
|---|---:|---:|---|---|
| Soldier | 60 | 3.2 | 30f / 12 | Telegraphs red |
| Heavy | 140 | 2.2 | 42f / 24 | Resists stagger |
| Hunter | 45 | 5.2 | 14f / 9 | 30% chance to sidestep a hit |

Attack token: with 2 or fewer enemies one attacks at a time; with more, two. The others circle at range.

## Equipment
Weapons multiply outgoing damage (blade 1.0, knife 1.25, machete 1.5, sword 1.9). Armor reduces incoming damage (10/20/35%).
Weapons and armor auto-equip only if better; medkits heal 40 (R key / Heal button).

## Waves
4 waves: 2 Soldiers; 2 Soldiers + Hunter; Heavy + Hunter + Soldier; Heavy + 2 Hunters.
