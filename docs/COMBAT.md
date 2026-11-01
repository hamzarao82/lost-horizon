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

## Lock-on
`Targeting` (scripts/combat/targeting.gd) picks the enemy nearest the screen centre within 14 m and a 75-degree cone of the camera, with a line-of-sight ray against the world. It drops the lock when the target dies or is freed, goes beyond 18 m, or is out of sight for more than 1.5 s.

| Input | Action |
|---|---|
| Middle mouse / Tab / right-stick click | `lock_on`: lock, press again to release |
| Mouse wheel / RB / LB | `target_next` / `target_prev`: switch left or right by screen position (wraps) |
| Touch "Lock" button | Lock; tapping again hops to the next enemy, and releases when there is only one |

While locked: attacks and strafing face the target (sprinting turns you to your movement), dodge still follows input, the camera eases toward keeping the target in view (mouse and touch look still nudge it), and a yellow arrow floats above the target.
Camera extras: FOV widens by 8 degrees while sprinting, and a soft lag follows player velocity. Shake is unchanged.
Tests: `tests/lockon_check.gd` (25 checks).
