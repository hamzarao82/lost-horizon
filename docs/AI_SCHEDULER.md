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

`ai_scheduler_check` (38): pure helpers, defaults, scheduler on vs off (first attack within 30 frames, same damage taken), crowd think count (36 thinks for 12 far enemies in 1 s instead of 720, never above 4 in a frame), flank fan-out, spacing, retreat, boss immunity, reinforcement cap. `explosive_barrel_check` (26): falloff, fuse, enemy and player damage, one shot, chain reaction, persistence.

## Not done

- No barrel is placed in any region; the component and its tests are provided, placement belongs to the region builders.
- No enemy config enables any tactic yet, so the shipped game behaves as before. Turning them on per region is a balance decision that needs a playtest.
- Defensive guard stance (block with a vulnerability window) from the plan is not built.
- No sounds, effects or explosion animation beyond the blinking fuse and ring; no performance measurement on web or Android.
