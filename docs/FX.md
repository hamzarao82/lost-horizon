# Combat effects (Fx)

`scripts/fx/fx_manager.gd`, autoload `Fx` (no `class_name`: it would clash with the autoload name).
Everything is created once in `_ready` and reused. A hit only repositions, recolors and restarts an existing node,
so there are no per-hit mesh, material or node allocations. CPUParticles3D only (Compatibility renderer, web, Android).

## What it shows
| Effect | Trigger | Pool |
|---|---|---|
| Hit sparks (white/yellow light, orange heavy at >= 20 damage) | `Enemy.damaged` | 8 x 12 particles |
| Floating damage number (white, yellow heavy, orange kill) | `Enemy.damaged` | 16 Label3D, shared with player numbers |
| Player damage number (red) and heal number (green) | player `HealthComponent.damaged` / `changed` | same 16 |
| Dust puff | player enters DODGE, hard landing (fall speed > 5 m/s), enemy dodges a hit | 4 x 8 particles |
| Death burst + expanding ground ring | `Enemy.defeated` | 3 x 24 particles, rings below |
| Windup ring (red, radius = attack range) | `Enemy.swing_started` (also the Warden's flurry) | 6 flat Sprite3D rings |
| Pickup shimmer on spawn and a brighter flash when collected | Pickup enters the tree / leaves it with the player within 2.5 m | 6 x 10 particles |

Total cap: 43 simultaneous effects. When a pool is full the oldest effect is stolen, so a flood of hits never grows anything.

## Budgets (checked in `tests/fx_check.gd`)
- 200 rapid hits add no nodes under `Fx`; pool sizes never change, including across repeated scene teardown.
- Active effects never exceed the caps; all effects are idle again about 1 s after the last hit.
- Particles use one shared `QuadMesh`, one unshaded alpha material and one fade `Gradient`.
- Rings share one 64x64 texture. Numbers are `Label3D` with `no_depth_test`; changing their text is the main cost, hence the cap of 16.
- Nothing ever calls `queue_free`. Pooled nodes live under `Fx`, so they survive scene reloads.

## Quality
`Fx.quality_scale` (0..1) follows `Settings.quality`: Low 0.4, Medium 0.7, High 1.0 (read through `/root/Settings`, null-safe,
refreshed on `Settings.changed`). Particle counts scale (`amount` is only changed when the setting changes, because it reallocates
the buffer). At 0 all particles and rings are off; damage numbers always stay.

## Wiring
`Fx` connects through `get_tree().node_added`: `Enemy` signals (`damaged`, `defeated`, `swing_started`, `was_hit`), the `Player`'s
`HealthComponent`, and `Pickup`. Gameplay scenes contain no effect code. `Enemy.damaged(amount, position, was_kill)` carries the real
damage after weapon scaling and the chest-height impact point; the Warden inherits it.

## Adding an effect
1. Add a cap constant and a `Pool` in `_build_pools()` (particles via `_make_particles`, or any Node3D).
2. Add a public method that does `var i := pool.take(_clock)`, recolors/moves the node, and calls `_fire(pool, i, position, life)`
   (or sets `pool.start[i]` / `pool.life[i]` and `_busy_until` for custom nodes animated in `_process`).
3. Honour `quality_scale` (return early at 0, add the pool to `_apply_particle_amounts`).
4. Connect it from `_on_node_added` or a signal handler, and add a cap/idle check to `tests/fx_check.gd`.
