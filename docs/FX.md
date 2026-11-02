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

## Milestone 002 additions (FX-HUD agent)

All of these are visual only: no gameplay number, hitbox or timing is read for any purpose except
*reading* attack frames, and nothing here is attached to gameplay scenes (Fx wires itself through `node_added`).

| Effect | Where | Budget |
|---|---|---|
| Weapon trail | `scripts/fx/weapon_trail.gd`, one per character that has `VisualRoot/WeaponPivot/Hitbox` | cap `Fx.MAX_TRAILS` = 8, <= 12 samples, 1 shared alpha material, 1 `ImmediateMesh` rebuilt only while the ribbon is alive |
| Spark variants | `Fx.spark` | same 8-emitter pool; light = fine/wide, heavy = chunky/tighter |
| Heavy impact | `Fx._on_enemy_damaged` | 1 ring (pool of 6) + 1 dust puff (pool of 4), only for damage >= 20 |
| Enemy hit reaction | `Fx._hit_react` | no nodes; a 0.14 s tween on the enemy's `VisualRoot.position` (position only, so scale, facing and the death tween are never fought) |
| Death burst | `Fx.death_burst` | the existing burst plus a 2.6 m ring and a 1.2 m bright core ring |
| Teleport | `scripts/fx/teleport_fx.gd` | per slot one light column, 3 afterimages (3 at quality >= 0.7, 2 below, 0 at quality 0), 1 streak between departure and arrival; all built once, <= 2 transparent layers each |
| Boss telegraph | `Fx._start_decal` / `_update_decal` | 2 sprites (outline + fill), Warden only |

### Weapon trail
- **Sampling** is on the physics tick, so it is one sample per active frame even when rendering is slow.
- **Blade points:** `TrailTip` and `TrailBase` markers under `VisualRoot/WeaponPivot` win (a hand-attached model can add them).
  Otherwise tip/base are derived from the `Weapon` node (`origin - basis.z * (0.3 + blade length)`); blade length comes from
  `WeaponModel.SPECS`. Derived points are sloped (tip raised 0.26, hilt lowered 0.3) because a horizontal slash lies in one
  plane and is edge-on to the third-person camera. Last fallback: a short vertical segment at the hitbox.
- **Colour:** the equipped weapon's rarity colour for the player, red for enemies. Fades over 0.15 s.
- **Quality:** `quality_scale == 0` records nothing.

### Boss telegraph decal
The wedge fill is driven by the boss's own `_attack_frames` and `_swing.startup_frames` (read-only), so it reaches the
rim on exactly the first active frame regardless of hit-stop or phase, then flashes white until the swing ends.

### Adding a new effect
Build its nodes once in `_build_pools` (or a dedicated class like `TeleportFx`), reuse them per play, scale amounts by
`quality_scale`, add a cap, and add a pool/count check to `tests/fx_check.gd`.

### Tests
`tests/fx_check.gd` (58 checks): pools and caps, trail sampling/fade/quality/cap/cleanup, hit-reaction recoil and kill cleanup,
teleport ghosts by quality and no growth over 50 plays, boss decal start/fill/end/quality.
