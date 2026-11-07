# Ranged combat (Milestone 8, shared with Milestone 9)

Status date: 2026-11-07. Legend: **Verified** = a test or a screenshot that was run; **Not verified** = not run.

## What exists
| Piece | File | Status |
|---|---|---|
| `Projectile` (pooled, ray-stepped, cap 12, lifetime 2.5 s) and its scene | `scripts/ai/ranged/projectile.gd`, `scenes/combat/Projectile.tscn` | Verified (`ranged_check`) |
| `RangedConfig` (data: shot, burst, band, cooldown, aim error, lead) | `scripts/ai/ranged/ranged_config.gd` | Verified; `validate()` rejects a telegraph under 0.6 s, recovery under 0.5 s, spacing under 0.25 s |
| `RangedBrain` (chase, band keeping, cover, telegraph, burst, recovery) | `scripts/ai/ranged/ranged_brain.gd` | Verified (`facility_commander_check`) |
| `CoverPoint` markers | `scripts/ai/ranged/cover_point.gd` | Class and line-of-sight helper verified; **no cover points are placed in any level yet**, and cover selection itself has no test |
| `EnemyConfig` (reusable enemy variant resource) | `scripts/ai/enemy_config.gd` | Verified through the Commander |
| Facility Commander | `resources/enemies/facility_commander.tres` | Verified |
| Shot and shove attack data | `resources/attacks/ranged_shot.tres`, `ranged_shove.tres` | Verified |
| Unique drop: Facility Trauma Kit | `resources/items/facility_trauma_kit.tres` | Verified (drops once, never after the claim) |

`Enemy` got a small additive hook set (an optional `ranged` export, one new state `RANGED_ATTACK` appended after `RETURN`, forwarding of CHASE and RANGED_ATTACK to the brain, a telegraph tint, cancel on stagger and on death). With no `ranged` config nothing changes; the existing suites run unmodified.

## How a ranged attack plays
1. **Telegraph** (40 frames = 0.67 s): the enemy stops, tints red, a red aim line shows the shot path, `swing_started` fires and the windup sound plays. The aim is **committed at 70%** of the telegraph, so moving afterwards sidesteps the burst.
2. **Burst:** 3 shots 19 frames (0.3 s) apart along the committed aim, with up to 4 degrees of random error and 40% of the perfect lead (never a perfect shot). Each shot first checks line of sight to the player: no shot through walls.
3. **Recovery** (36 frames = 0.6 s): the enemy stands still. This is the punish window.
4. A hit on the enemy at any time before the last shot **staggers it and cancels the attack** (no shot is fired by an interrupted attack).

Between attacks the enemy keeps 7 to 12 m from the player: it backs away when closer, strafes inside the band (direction flips every 1.2 to 2.4 s or when blocked), and walks toward a cover point or the player when it has no line of sight or is too far. Within 2 m it uses its melee swing (a shove, 28-frame telegraph) instead of shooting. If it cannot retreat (blocked for 0.8 s) it may fire at close range.

## Damage path
A projectile calls `receive_hit(attack, from, damage_scale)` on the player, the same call melee uses. Armor, `Progression.incoming_multiplier()`, and dodge i-frames therefore apply exactly once; a projectile that meets an invulnerable player is consumed without damage. Per-hit damage is 8 times the shooter's `damage_mult` (1.0 at level 1; `EnemyScaling` raises it with player level).

## Numbers (from data, asserted by tests)
| | Value | Rule |
|---|---|---|
| Telegraph | 40 frames, measured 41 | at least 36 |
| Shot spacing | 18 frames, measured 19 | at least 15 |
| Recovery after the last shot | 36 frames, measured 36 | at least 30 |
| Damage per projectile | 8 | once per projectile |
| Burst | 3 shots | at most 24 damage per burst if every shot lands |
| Live projectiles | at most 12 | refused beyond the cap |
| Commander | 110 health, 30 armor, speed 3.8 | loot tier elite plus the unique kit |

## Tests
`tests/ranged_check.gd` (23 checks): data fairness, hit once for exactly 8, wall stops the shot, i-frames avoid the hit, armor drains first, live cap 12 and pool reuse leave the node count flat, lifetime expiry, straight-up shots do not error.
`tests/facility_commander_check.gd` (32 checks): configuration, the real timeline (telegraph, spacing, recovery, committed aim, no extra shot in recovery), interruption by a hit, no attack without line of sight, retreat inside the band, shove at close range, unique drop once, ally alert, other enemies unchanged.

## Not done or not verified
- **No new animation clips.** The shot is shown by scrubbing the existing `shockwave_cast` clip over the attack timeline (and `light_2` for the shove); there is no aiming or firing pose. The Commander uses the soldier model with a blue-grey tint, no distinct model, and no visible weapon that fires.
- **No audio for the shot.** It reuses `enemy_swing_windup` (telegraph) and `swing_light` (shot); there is no gunshot, impact or whiz sound. Nobody has listened to either.
- **Cover points are not placed anywhere**, so in play the Commander has no cover to use until a level adds markers; cover selection has no test.
- **Several ranged enemies can fire at once.** The melee attack token is not used; only the 12-projectile cap limits them. Group tuning is untested.
- **Projectiles are small at range** (a glowing orange capsule 0.22 m wide, 1.1 m long): visible at 9 m in a screenshot, but no human has judged whether it can be read and dodged in motion.
- **No human playtest:** difficulty, dodge timing and whether three shots feel fair are unjudged.
- **Not run on web or Android.** A ray cast per live projectile per physics frame is cheap, but it was not measured.
- Milestone 9's Fortress Infantry, Tactical Commander and the Director are not built; they would be new `EnemyConfig` resources on this framework.
