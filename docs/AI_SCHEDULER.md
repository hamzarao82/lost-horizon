# AI scheduler, tactics and explosive barrel (Milestone 11)

Everything here is opt-in. A plain `Enemy` or `EnemyConfig` keeps the original behaviour: the new fields default to off, and `run_tests`, `boss_check`, `patrol_check`, `arena_check` and the other existing suites pass unmodified.

## What exists

| Piece | Where | Switch |
|---|---|---|
| Staggered think scheduler | `scripts/ai/ai_scheduler.gd`, `Enemy._scheduled_chase` | `scheduled` |
| Flank slots | `AIScheduler.flank_slot/flank_angle`, `Enemy._approach_dir` | `flank_slots` |
| Spacing | `AIScheduler.separation` | `spacing` |
| Low-health retreat | `Enemy._after_tactical_hit` | `retreat_health_fraction` (0 = never) |
| Capped reinforcement call | `Enemy._raise_alarm` (existing ally-alert hook) | `reinforcement_cap` (0 = none) |
| Explosive barrel | `scripts/world/explosive_barrel.gd` | a component, no switch |

All five Enemy fields are also on `EnemyConfig` (copied by `apply`), so a new variant is data, not a new class.

## Scheduler

Chase decisions run every 0.1 s (within 6 m of the target), 0.2 s (within 12 m) or 0.3 s (farther). The attack-token holder thinks every frame. A global budget of 4 thinks per frame spreads a crowd over several frames; an enemy denied a think simply tries again next frame. Attack, stagger, patrol and ranged states are not throttled, so frame data is untouched. Between thinks the previous velocity carries on.

## Tactics

- **Flank slots:** enemies with `flank_slots` chasing the same target (within 18 m) are ordered by instance id and fan out by 0.6 rad per slot while farther than `attack_range + 1.5`; the last stretch is head-on.
- **Spacing:** enemies waiting on the ring are pushed away from neighbours closer than 1.6 m.
- **Retreat:** once health falls to the configured fraction the enemy backs away for 2.5 s, once per life. Bosses (`Warden`, `Director`, `StageBossEnemy`) ignore both retreat and reinforcement.
- **Reinforcement:** the first hit that does not kill calls up to `reinforcement_cap` idle/patrolling allies within 10 m through `receive_ally_alert`. Existing `coordinate_alarm` enemies are unchanged (cap 0 = unlimited as before).

## Explosive barrel

`ExplosiveBarrel` (a `StaticBody3D` on the enemy collision layer, so the player's weapon hitbox lights it). A hit starts a 1.2 s fuse with a blinking body and a red blast-radius ring; then every enemy and the player inside `radius` (default 4.5 m) take `damage` (default 45) scaled from 100% at the centre to 25% at the edge, neighbouring barrels inside the radius ignite, and the barrel frees itself. One shot only. With `region_id` and `barrel_id` set, the destroyed state is stored through `PersistentIds` (claim `barrel_<id>`), so a reload does not bring it back.

## Tests

`ai_scheduler_check` (38), `explosive_barrel_check` (26), `guard_stance_check` (20), `tactics_live_check` (51).

## Guard stance

`Enemy.guard_reduction` (0 = off, max 0.9) and `guard_vulnerable_seconds` (default 1.0), also on `EnemyConfig` and `FacilityEnemyConfig`. Rule: while an enemy is chasing (not attacking, staggered, idle or retreating) and the attacker stands inside its front 120 degrees, a light hit does `(1 - guard_reduction)` of its damage and never staggers it; that block opens a vulnerability window in which hits land in full and stagger as normal. Attacks whose id starts with `heavy` or `sprint`, ring (`aoe_radius > 0`) attacks, and hits from the side or behind bypass the guard. `Enemy._guard_blocks` holds the rule; `tests/guard_stance_check.gd` (20) covers the default, the block, the window, every bypass and every non-chasing state.

## Live in the real configs

| Config | Region | Tactics on |
|---|---|---|
| Security Guard (`facility_security_guard`) | Research Complex | scheduler, flank slots, spacing, retreat at 20% health, reinforcement cap 1 |
| Heavy Facility Guard (`facility_heavy_guard`) | Research Complex | scheduler, spacing, guard 0.4 (1.2 s window), reinforcement cap 1 |
| Fortress Infantry, Elite Security Soldier | Iron Fortress | reinforcement cap 2 (ranged: only the alert call applies, the ranged brain has its own movement) |
| Heavy Assault Unit | Iron Fortress | guard 0.5 (1.0 s window), reinforcement cap 1 |

Bosses (Warden, Director, Captain, stage bosses, Subject Zero, the Commanders) have everything off, asserted by `tests/tactics_live_check.gd` (51 checks). The same test runs fights: four tactics guards all die within 3000 frames with the retreat triggered, a retreater is back in the chase after 2.5 s and can be finished off, a guarding heavy still dies to light hits, and five idle allies yield exactly `reinforcement_cap` responders, once. Dead Coast, Blackwood and the Outpost 17 patrols spawn bare scenes (`PatrolSoldier.tscn`, `HeavySoldier.tscn`) and have no config, so they still play as before.

## Barrels placed

`scripts/world/barrel_placement.gd` (`BarrelPlacement.LAYOUTS`) places four barrels in each of Outpost 17 (arena flanks and the beach approach), the Research Complex laboratory and the Iron Fortress barracks, each region adding one hook line (`BarrelPlacement.build`). Ids are `[a-z0-9_]`, unique, and persisted through `PersistentIds` with the region id. The test checks every barrel is at least 3 m from the main route, inside the region walls, not inside another solid (a physics query of the built regions), and that a destroyed barrel stays gone after the region is rebuilt. The route probes and keep-clear checks of both regions still pass. The explosion has a procedural sound (`explosion.wav`, appended to `tools/gen_sfx.gd`; every earlier wav is byte-identical, checked by md5) and reuses the pooled death burst and ground ring from `Fx`; it has never been listened to.

## Not done

- Guard stance and tactics have never been played by a person; values are conservative guesses.
- Ranged enemies do not retreat, flank or space (their brain owns movement); Dead Coast, Blackwood and Outpost 17 enemies have no config, so no tactics there.
- No web or Android performance measurement.
